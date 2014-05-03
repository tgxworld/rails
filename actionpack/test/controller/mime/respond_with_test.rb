require 'abstract_unit'
require 'controller/fake_models'
require 'benchmark'
require 'benchmark/ips'

class RespondWithController < ActionController::Base
  respond_to :html, :json, :touch
  respond_to :xml, :except => :using_resource_with_block
  respond_to :js,  :only => [ :using_resource_with_block, :using_resource, 'using_hash_resource' ]

  def using_resource
    respond_with(resource)
  end

  def using_hash_resource
    respond_with({:result => resource})
  end

  def using_resource_with_block
    respond_with(resource) do |format|
      format.csv { render :text => "CSV" }
    end
  end

  def using_resource_with_overwrite_block
    respond_with(resource) do |format|
      format.html { render :text => "HTML" }
    end
  end

  def using_resource_with_collection
    respond_with([resource, Customer.new("jamis", 9)])
  end

  def using_resource_with_parent
    respond_with(Quiz::Store.new("developer?", 11), Customer.new("david", 13))
  end

  def using_resource_with_status_and_location
    respond_with(resource, :location => "http://test.host/", :status => :created)
  end

  def using_invalid_resource_with_template
    respond_with(resource)
  end

  def using_options_with_template
    @customer = resource
    respond_with(@customer, :status => 123, :location => "http://test.host/")
  end

  def using_resource_with_responder
    responder = proc { |c, r, o| c.render :text => "Resource name is #{r.first.name}" }
    respond_with(resource, :responder => responder)
  end

  def using_resource_with_action
    respond_with(resource, :action => :foo) do |format|
      format.html { raise ActionView::MissingTemplate.new([], "bar", ["foo"], {}, false) }
    end
  end

  def using_responder_with_respond
    responder = Class.new(ActionController::Responder) do
      def respond; @controller.render :text => "respond #{format}"; end
    end
    respond_with(resource, :responder => responder)
  end

  def respond_with_additional_params
    @params = RespondWithController.params
    respond_with({:result => resource}, @params)
  end

protected
  def self.params
    {
        :foo => 'bar'
    }
  end

  def resource
    Customer.new("david", request.delete? ? nil : 13)
  end
end

class InheritedRespondWithController < RespondWithController
  clear_respond_to
  respond_to :xml, :json

  def index
    respond_with(resource) do |format|
      format.json { render :text => "JSON" }
    end
  end
end

class RenderJsonRespondWithController < RespondWithController
  clear_respond_to
  respond_to :json

  def index
    respond_with(resource) do |format|
      format.json { render :json => RenderJsonTestException.new('boom') }
    end
  end

  def create
    resource = ValidatedCustomer.new(params[:name], 1)
    respond_with(resource) do |format|
      format.json do
        if resource.errors.empty?
          render :json => { :valid => true }
        else
          render :json => { :valid => false }
        end
      end
    end
  end
end

class CsvRespondWithController < ActionController::Base
  respond_to :csv

  class RespondWithCsv
    def to_csv
      "c,s,v"
    end
  end

  def index
    respond_with(RespondWithCsv.new)
  end
end

class EmptyRespondWithController < ActionController::Base
  def index
    respond_with(Customer.new("david", 13))
  end
end

class RespondWithControllerTest1 < ActionController::TestCase
  tests RespondWithController

  def setup
    super
    @request.host = "www.example.com"
    Mime::Type.register_alias('text/html', :iphone)
    Mime::Type.register_alias('text/html', :touch)
    Mime::Type.register('text/x-mobile', :mobile)
  end

  def teardown
    super
    Mime::Type.unregister(:iphone)
    Mime::Type.unregister(:touch)
    Mime::Type.unregister(:mobile)
  end

  def test_using_resource
    iterations = 1000

    Benchmark.bm(30) do |bm|
      bm.report 'FunctionalTest' do
        iterations.times do
          @request.accept = "application/xml"
          get :using_resource
          assert_equal "application/xml", @response.content_type
          assert_equal "<name>david</name>", @response.body
        end
      end
    end
  end
end

class RespondWithControllerTest < ActionDispatch::IntegrationTest
  def setup
    super
    Mime::Type.register_alias('text/html', :iphone)
    Mime::Type.register_alias('text/html', :touch)
    Mime::Type.register('text/x-mobile', :mobile)
  end

  def teardown
    super
    Mime::Type.unregister(:iphone)
    Mime::Type.unregister(:touch)
    Mime::Type.unregister(:mobile)
  end

  def test_using_resource
    iterations = 1000

    Benchmark.bm(30) do |bm|
      bm.report 'IntegrationTest' do
        iterations.times do
          get '/respond_with/using_resource', {}, { 'ACCEPT' => "application/xml" }
          assert_equal "application/xml", response.content_type
          assert_equal "<name>david</name>", response.body
        end
      end
    end
  end
end

# class FlashResponder < ActionController::Responder
#   def initialize(controller, resources, options={})
#     super
#   end

#   def to_html
#     controller.flash[:notice] = 'Success'
#     super
#   end
# end

# class FlashResponderController < ActionController::Base
#   self.responder = FlashResponder
#   respond_to :html

#   def index
#     respond_with Object.new do |format|
#       format.html { render :text => 'HTML' }
#     end
#   end
# end

# class FlashResponderControllerTest < ActionDispatch::IntegrationTest
#   def test_respond_with_block_executed
#     get '/flash_responder/index'
#     assert_equal 'HTML', response.body
#   end

#   def test_flash_responder_executed
#     get '/flash_responder/index'
#     assert_equal 'Success', flash[:notice]
#   end
# end
