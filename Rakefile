require 'rake'
require 'bundler/gem_tasks'
require 'neo4j-core'
load 'neo4j/tasks/neo4j_server.rake'
load 'neo4j/tasks/migration.rake'

desc 'Generate YARD documentation'
task 'yard' do
  abort("can't generate YARD") unless system('yardoc - README.md')
end

desc 'Run neo4j.rb specs'
task 'spec' do
  success = system('rspec spec')
  abort('RSpec neo4j failed') unless success
end

require 'rake/testtask'
Rake::TestTask.new(:test_generators) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end

# Adding test/lib directory to rake test.
Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.test_files = FileList['test/lib/*_test.rb']
  test.verbose = true
  desc "Test tests/lib/* code"
end

desc 'Generate coverage report'
task 'coverage' do
  ENV['COVERAGE'] = 'true'
  rm_rf 'coverage/'
  task = Rake::Task['spec']
  task.reenable
  task.invoke
end

task default: ['spec']
