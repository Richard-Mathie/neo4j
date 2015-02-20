require 'erb'
require 'yaml'
require 'active_support/dependencies'
require 'neo4j/railtie'

module Neo4j

#=============================================    
#=============================================    
  class Fixture #:nodoc:
    include Enumerable

    class FixtureError < StandardError #:nodoc:
    end

    class FormatError < FixtureError #:nodoc:
    end

    attr_reader :model_class, :fixture

    def initialize(fixture, model_class)
      @fixture     = fixture
      @model_class = model_class
    end

    def class_name
      model_class.name if model_class
    end

    def each
      fixture.each { |item| yield item }
    end

    def [](key)
      fixture[key]
    end

    alias :to_hash :fixture

    def find
      if model_class
        model_class.find(fixture[model_class.primary_key])
      else
        raise FixtureClassNotFound, "No class attached to find."
      end
    end
  end # Fixture

#=============================================    
#=============================================
  module FixtureAccessor
    #this is where we set up methods corrsponding to each fixture file so we can find the
    #fixtures by name (eg state_machines(:bar) => StateMachine built from fixture bar)
    def setup_fixture_accessors(*fixture_set_names)
      #create the cache if not existing 
      methods = Module.new do
        fixture_set_names.each do |fs_name|
          fs_name = FixtureSet.default_fixture_set_name(fs_name)
          fs_klass_name = FixtureSet.default_fixture_model_name(fs_name)
          accessor_name = fs_name.tr('/', '_').to_sym
          
          #define the method
          #interrogates the fixture cache, returning either an existing object or
          #a new object of the right class with id only set
          method_sym=define_method(accessor_name) do |*fixture_names|

            fixture_set_cache=FixtureSet.fixture_cache[fs_name]
            fixture_base_klass=FixtureSet.model_namespace.const_get(fs_klass_name)
            instances = fixture_names.map do |f_name|
              #now find each fixture in the cache, creating a blank object of the correct
              #class if it doesn't exist 
              if self.rows[f_name].keys.include? "type"
                binding.pry
                fixture_klass=FixtureSet.model_namespace.const_get(self.rows[f_name]["type"])
              else
                fixture_klass=fixture_base_klass
              end
              #ensure that our model class has an id method defines which can then
              #be used to set up relatiosnhips between fixtures
              unless fixture_klass.id_property? && fixture_klass.id_property_name==:test_id
                fixture_klass.class_eval do
                   STDERR.puts "Adding test_id to #{self}"     
                  id_property :test_id
                end
              end
              
              fixture_set_cache[f_name.to_s] ||= fixture_klass.create!(test_id: FixtureSet.identify(f_name))
            end

            instances.size == 1 ? instances.first : instances
          end
          
          #private accessor_name
        end #Neo4j::FixtureAccessor.setup_fixture_accessors(fixture_set_names)
      end
      include methods
      methods
    end # setup_fixture_accessors
  end #FixtureAccessor

#=============================================    
#=============================================    
  class FixtureSet
  
    class << self
      attr_accessor :fixture_cache
      attr_accessor :model_namespace
      attr_accessor :fixtures_module
    end
    #include Neo4j::FixtureAccessor
    extend Neo4j::FixtureAccessor
    
    self.fixture_cache||=Hash.new do |cache, fs_name|
      cache[fs_name]=Hash.new 
    end
    self.model_namespace=Kernel
  
    MAX_ID = 2 ** 30 - 1

    def self.create_fixtures(fixtures_directory, fixture_set_names, class_names = {})
      self.fixtures_module=setup_fixture_accessors(*fixture_set_names)
      self.create_fixture_objects(fixtures_directory, *fixture_set_names)
    end
  
    def self.reset_cache
      ### puts "Resetting database"
      fixture_cache.clear
      Neo4j::Session.current._query('MATCH (n) OPTIONAL MATCH (n)-[r]-() DELETE n,r')
    end
    
    def self.identify(label)
      Zlib.crc32(label.to_s) % MAX_ID
    end

    
    #turn a fixture name to a class name
    def self.default_fixture_model_name(fixture_set_name) # :nodoc:
      fixture_set_name.to_s.singularize.camelize
    end
    
    #turn a fixture name to a set name
    def self.default_fixture_set_name(fixture_set_name) # :nodoc:
      #fixture_set_name.to_s.camelize(:lower).pluralize()
      fixture_set_name.to_s.underscore.pluralize()
    end
    
    #turn a fixture name to a fixtuer set file name
    def self.default_fixture_file_name(fixture_set_name) # :nodoc:
      fixture_set_name.to_s.underscore.pluralize()
    end
    
    #set 
    def self.create_fixture_objects(fixtures_directory, *fixture_set_names)
      fixture_set_names.collect do |fixture_set_name|
        FixtureSet.new(fixtures_directory, fixture_set_name)
      end
    end

#=============================================    
    
    attr_reader :name, :path
    attr_accessor :rows, :fixtures
    
    def initialize(fixtures_directory, fixture_set_name)
      @name=FixtureSet.default_fixture_set_name(fixture_set_name)
      @fs_file_name= FixtureSet.default_fixture_file_name(fixture_set_name)+'.yml'
      @path=fixtures_directory
      @file=File.join(@path, @fs_file_name)
      self.rows
      
      #Make the fixtures exist
      extend self.class.fixtures_module
      self.send(name.to_sym, *self.rows.keys)
      #FixtureSet.fixture_cache[fs_name]fixture_set_cache[f_name.to_s] ||= fixture_klass.create!(test_id: FixtureSet.identify(f_name))
      #run through the fixture objects, updating the attributes and relationships
      self.rows.each do |fixture_name, attribute_hash|
#        if attribute_hash.keys.include? "type"
#          binding.pry
#        end
        fixture=FixtureSet.fixture_cache[name][fixture_name]
        klass = fixture.class
        attribute_hash.inject(fixture) do |fix,(attr_name, value)|
          attr_name = attr_name.to_sym
          #Check if the property is a relationship.
          #If it is we have to set the value as the correct node in the cache
          if klass.association? attr_name
            association = klass.associations[attr_name]
            # Check if the value given is an Object or a string
            if value.is_a? String
              #binding.pry
              values=value.split(', ').map{|v|v.strip}
              # if we know the target class we can find the fixture in the fixture set
              model_class = association.target_class_name_or_nil.tr('::','')
              model_set = FixtureSet.default_fixture_set_name(model_class)
              if !model_set.nil?
                #value = FixtureSet.fixture_cache[model_set][value]
                values=values.map{|v|FixtureSet.fixture_cache[model_set][v]}
              else
                # look in all fixtures ** Costly **
                values = FixtureSet.fixture_cache.values.inject({}){|h,v| h.merge(v)}
              end
              
              case association.type
                when :has_many
                  values.each{|v|fixture[attr_name]<< v }
                when :has_one
                  fixture[attr_name]=values.first
                else
                  raise Fixture::FixtureError, "Undefined assosiation type #{@association.type} when processing attribute:#{attr_name} with value:#{values} for fixture:#{fixture_name}. I dont know what to do with that.The exact error was:\n  #{error.class}: #{error}", error.backtrace
              end
              
            elsif value.is_a? Object
              # nothing at the moment
            end
          #Assign value to attribute
          elsif !fixture.props.key attr_name
#            if value=="test" || value.nil?
#              binding.pry
#            end
            fixture[attr_name]=value
          elsif fixture.public_methods.include? attr_name
            fixture.send(attr_name,value)
          else
            fail 'fixture attribute #{attr_name} not defined in model #{fixture.class}'
          end
        end
        #Update the fixture in the database
        fixture.save!
      end
      
      self
    end # initialize


    def rows
      return @rows if @rows

      begin
        #load the yaml data into a hash (of hashes - each key value pair is a setter
        # method, with a  value)
        ### puts "loading database"
        data = YAML.load(ERB.new(IO.read(@file)).result)
      rescue ArgumentError, Psych::SyntaxError => error
        raise Fixture::FormatError, "a YAML error occurred parsing #{@file}. Please note that YAML must be consistently indented using spaces. Tabs are not allowed. Please have a look at http://www.yaml.org/faq.html\nThe exact error was:\n  #{error.class}: #{error}", error.backtrace
      end
      @rows = data ? validate(data) : {}
    end # rows

     # Validate our unmarshalled data.
    def validate(data)
      unless Hash === data || YAML::Omap === data
        raise Fixture::FormatError, 'fixture is not a hash'
      end

      raise Fixture::FormatError unless data.all? { |name, row| Hash === row }
      data
    end # validate

  end # FixtureSet

#=============================================    
#=============================================    
#module Neo4j
  module TestFixtures
    def self.included(mod)
      mod.extend ClassMethods
      mod.extend Neo4j::FixtureAccessor
      attr_accessor :fixture_set_names
    end

    def before_setup
      FixtureSet.reset_cache
      setup_fixtures
    end
  
    def after_teardown
      teardown_fixtures
    end
    
   #=============================================    
    module ClassMethods
      attr_accessor :fixture_table_names

      def fixtures(*fixture_set_names)
        if fixture_set_names.first == :all
          fixture_set_names = Dir["#{fixture_path}/{**,*}/*.{yml}"]
          fixture_set_names.map! { |f| f[(fixture_path.to_s.size + 1)..-5] }
        else
          fixture_set_names = fixture_set_names.flatten.map { |n| n.to_s }
        end

        self.fixture_table_names = fixture_set_names
        #require_fixture_classes(fixture_set_names, self.config)
        setup_fixture_accessors(*fixture_set_names)
      end
            
      def i_am_neo
        puts "yes I am"
      end
      
    
    end # end ClassMethods
    
    def setup_fixtures
      FixtureSet.create_fixtures(fixture_path, fixture_table_names, class_names = {})
    end
    
    def teardown_fixtures
      FixtureSet.reset_cache
    end
    
  end # end TestFixtures

end #end Neo4j module

module Neo4j::RelIDAccessor
  def def_id_accessors(*rel_names)
    if rel_names.length()==0
      rel_names=self.associations.keys
    end
    methods = Module.new do
      rel_names.each do |rel_name|
        accessor_name = (rel_name.to_s+'_id').to_sym
        
        #define the method
        method_sym=define_method(accessor_name) do |id=nil|
          ActiveSupport::Deprecation.warn("Deprechiated Nolonger need to traverse IDs when using neo4j")
          self[rel_name].nil? ? nil : self[rel_name].neo_id
        end
      end
    end
    include methods
    methods
  end # setup_fixture_accessors
end

