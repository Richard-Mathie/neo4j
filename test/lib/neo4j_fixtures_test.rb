require 'test_helper'

require 'minitest/autorun'
require 'minitest/spec'
#require 'minitest-spec-rails'

require 'pry'

require 'neo4j/neo4j_fixtures.rb'
require 'neo4j'

include Neo4j

class TestFixtureObject#  < ActiveRecord::Base
  include Neo4j::ActiveNode
  #binding.pry
  property :timestamp, type: Time #, limit: 3
  property :name, type: String
  property :bool, type: Boolean
  
  # Some relationships
  has_one :out , :next     , model_class: TestFixtureObject #, type: :linked
  has_one :in  , :previous , model_class: TestFixtureObject #, type: :linked
  has_one :both, :sister   , model_class: TestFixtureObject , type: :sybling
  has_many :in , :friends  , model_class: TestFixtureObject, type: :knowlege
  has_one :out, :test1, model_class: TestFixtureObject
  has_many :out, :test2, model_class: TestFixtureObject
  has_one :out, :test3
end

describe FixtureSet do
  test_fixture_object_name = 'testFixtureObject'
  test_fixture_object_name=FixtureSet.default_fixture_set_name(test_fixture_object_name).to_sym
  
  before do
    
    fixture_path = Rails.root.join('test/fixtures')
    # Clean the database
    FixtureSet.reset_cache
    FixtureSet.fixture_cache.must_be_empty
    #Initilise the accsessor
    FixtureSet.setup_fixture_accessors(test_fixture_object_name)
    FixtureSet.send(:public,test_fixture_object_name) # though this will break if it dosent?!
    FixtureSet.method_defined?(test_fixture_object_name).must_equal true
    #Create the Object
    FixtureSet.create_fixtures(fixture_path,test_fixture_object_name)
  end


  it 'must create a fixture association' do
    # must define accessor method public to check that it exists
    FixtureSet.fixture_cache.wont_be_empty
    FixtureSet.fixture_cache[test_fixture_object_name].must_be_kind_of Hash
  end
    
  it 'must be have built the database correctly' do  
    # pull out the chain
    FixtureSet.reset_cache
    FixtureSet.create_fixture_objects(fixture_path,test_fixture_object_name)
    # MATCH (n:TestFixtureObject{name:'2'}),n-[r:NEXT*0..]->m return m
    TestFixtureObject.where(name: "0").query_as(:n).match("n-[r:NEXT*0..]->m").pluck(:m).count.must_equal 5
    TestFixtureObject.where(name: "2").query_as(:n).match("n-[r:NEXT*0..]->m").pluck(:m).count.must_equal 3
    TestFixtureObject.where(name: "4").query_as(:n).match("n<-[r:PREVIOUS*0..]-m").pluck(:m).count.must_equal 5
    TestFixtureObject.where(name: "4").query_as(:n).match("n<-[r:PREVIOUS*0..]-m").pluck(:m).map{
    |f|f.name}.must_equal ["4", "3", "2", "1", "0"]
    TestFixtureObject.find_by(test_id: FixtureSet.identify("foo")).name.must_equal "0"
  end

  it 'can load the fixture set and should be different to the database' do
    FixtureSet.reset_cache
    fs =  FixtureSet.new(fixture_path, test_fixture_object_name)
    fixs = fs.test_fixture_objects :foo, :bar
    TestFixtureObject.find_by(test_id: FixtureSet.identify("foo")).wont_be_same_as fixs[0]
  end
# 
end
 
describe TestFixtureObject do
  include Neo4j::TestFixtures
  #binding.pry
  fixtures :test_fixture_objects, :transitions
  
  it 'must load the fixtures' do
    #binding.pry
    foo = test_fixture_objects(:foo)
    foo.must_be_instance_of TestFixtureObject
    foo.must_be_kind_of TestFixtureObject
    foo.name.must_equal "0"
  end
  
  it 'must load the fixtures and link them correctly' do
    #binding.pry
    foo = test_fixture_objects(:foo)
    binding.pry
    chain = foo.query_as(:n).match("n-[r:NEXT*0..]->m").pluck(:m)
    chain.map{|f| f.name}.must_equal ["0", "1", "2", "3", "4"]
    chain[-1].must_equal test_fixture_objects(:norf)
  end
end
