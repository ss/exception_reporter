require 'test/unit'
require File.dirname(__FILE__) + '/../../../../config/environment'
require 'fileutils'
require 'action_controller/test_process'
require 'mocha'

class ExceptionHandlerTest < Test::Unit::TestCase


  EXCEPTIONS_DIR = (ENV['TEMP'] || ENV['TMP'] || '.') + '/exceptions'

  class TestController < ActionController::Base
    ActionController::Routing::Routes.draw{|map| map.raise '/raise', :controller=>'exception_handler_test/test', :action=>'do_raise'}
    def do_raise
      raise params[:ex].constantize.new(params[:msg])
    end
  end

  def setup
    @controller = TestController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
    FileUtils.mkdir_p(EXCEPTIONS_DIR)
    @today = Date.today.strftime("%Y-%m-%d")
  end

  def teardown
    FileUtils.rm_rf(EXCEPTIONS_DIR)
  end

  def test_init_rb
    assert ActionController::Base.respond_to?(:saves_exceptions), 'ActionController::Base should respond to :saves_exceptions'
  end

  def test_saves_exceptions_with_hostname
    TestController.saves_exceptions(:hostname=>'foo', :exceptions_dir=>EXCEPTIONS_DIR)
    get :do_raise, :ex=>'Exception', :msg=>'test exception'
    lines = read_file(Exception).join
    assert_match 'Hostname: foo', lines, "Hostname should be emitted"
  end

  def test_saves_exceptions_only_matched
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR, :only=>[:Exception])
    get :do_raise, :ex=>'Exception', :msg=>'test exception'
    assert_file_written(Exception)
  end

  def test_saves_exceptions_only_unmatched
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR, :only=>[:RuntimeError])
    get :do_raise, :ex=>'Exception', :msg=>'test exception'
    assert_file_not_written(Exception)
  end

  def test_saves_exceptions_except_matched
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR, :except=>[:Exception])
    get :do_raise, :ex=>'Exception', :msg=>'test exception'
    assert_file_not_written(Exception)
  end

  def test_saves_exceptions_except_unmatched
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR, :except=>[:RuntimeError])
    get :do_raise, :ex=>'Exception', :msg=>'test exception'
    assert_file_written(Exception)
  end

  def test_saves_exceptions_log_when_executes_in_controller_instance
    called = false
    log_when = Proc.new{|ex| raise "log_when should execute in controller instance" unless self.class.name.index('Controller') ; called = true}
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR, :log_when=>log_when)
    get :do_raise, :ex=>'Exception', :msg=>'test exception'
    assert_equal true, called, "log_when should've been invoked"
  end

  def test_saves_exceptions_log_when_receives_exception_as_parameter
    called = false
    log_when = Proc.new{|ex| raise "log_when parameter should be an exception (instead of #{ex.class.name})" unless ex.is_a?(Exception) ; called = true}
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR, :log_when=>log_when)
    get :do_raise, :ex=>'RuntimeError', :msg=>'test exception'
    assert_equal true, called, "log_when should've been invoked"
  end

  def test_saves_exceptions_writes_file_if_log_when_returns_true
    log_when = Proc.new{|ex| true}
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR, :log_when=>log_when)
    get :do_raise, :ex=>'RuntimeError', :msg=>'test exception'
    assert_file_written(RuntimeError)
  end

  def test_saves_exceptions_does_not_write_file_if_log_when_returns_false
    log_when = Proc.new{|ex| false}
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR, :log_when=>log_when)
    get :do_raise, :ex=>'RuntimeError', :msg=>'test exception'
    assert_file_not_written(RuntimeError)
  end


  def test_reporter_no_mail_to
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR)
    get :do_raise, :ex=>'RuntimeError', :msg=>'test exception'

    html = ExceptionHandler::Reporter.run(:hostname=>'foo', :date=>@today, :controller_class=>TestController)

    assert_match 'RuntimeError', html
    assert_match 'test#do_raise', html
    assert_match "http://foo/exceptions/RuntimeError/#{@today}", html
  end

  def test_reporter_with_mail_to
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR)
    get :do_raise, :ex=>'RuntimeError', :msg=>'test exception'

    Net::SMTP.any_instance.expects(:start)
    ExceptionHandler::Reporter.run(:mail_to=>'foo@bar.com', :hostname=>'foo', :date=>@today, :controller_class=>TestController)
  end


private

  def read_file(name)
    assert_file_written(name)
    open(Dir["#{dir(name)}/**/*.txt"].first){|f| f.readlines}
  end

  def assert_file_written(name)
    assert File.exists?(dir(name)), "#{dir(name)} directory should exist"
  end

  def assert_file_not_written(name)
    assert !File.exists?(dir(name)), "#{dir(name)} directory should NOT exist"
  end

  def dir(name)
    "#{EXCEPTIONS_DIR}/#{name}"
  end

end
