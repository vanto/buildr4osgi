# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.

# Methods added to Project for compiling, handling of resources and generating source documentation.
module OSGi
  
  MISSING = "missing"
  
  RESOLVED = {}
    
  
  module BundleCollector #:nodoc:
    
    attr_accessor :bundles, :projects, :project_dependencies
    
    # Collects the bundles associated with a project.
    # Returns them as a sorted array.
    #
    def collect(project)
      info "** Collecting dependencies for #{project}"
      @bundles = []
      @projects = []
      dependencies = project.manifest_dependencies().each {|dep| ; _collect(dep)}
      @projects.delete project # Remove our own reference if it was added.
      info "** Done collecting dependencies for #{project}"
      return dependencies
    end
    
    # Collects the bundles associated with the bundle
    # 
    def _collect(bundle)
      if bundle.is_a?(Bundle)
        unless ::OSGi::RESOLVED[bundle]
          resolved = bundle.resolve
          trace "Resolving #{bundle}: #{resolved}"
          ::OSGi::RESOLVED[bundle] = resolved.nil? ? ::OSGi::MISSING : resolved
        end
        bundle = ::OSGi::RESOLVED[bundle]
        unless bundle.nil? || bundle == ::OSGi::MISSING
          if bundle.is_a?(Buildr::Project)
            @projects << bundle
          elsif !(@bundles.include? bundle)
            @bundles << bundle
            @bundles |= bundle.fragments      
            (bundle.bundles + bundle.imports).each {|import|
              _collect import
            }
          end
        end
      elsif bundle.is_a?(BundlePackage)
        unless ::OSGi::RESOLVED[bundle]
          resolved = bundle.resolve
          trace "Resolving #{bundle}: #{resolved}"
          ::OSGi::RESOLVED[bundle] = (resolved.nil? || (resolved.is_a?(Array) && resolved.empty?)) ? ::OSGi::MISSING : resolved
        end
        bundle = ::OSGi::RESOLVED[bundle]
        unless bundle.nil? || bundle == ::OSGi::MISSING
          bundle.each {|b| 
            if b.is_a?(Buildr::Project)
              @projects << b
            elsif !(@bundles.include? b)
              @bundles << b
              @bundles |= b.fragments  
              (b.bundles + b.imports).each {|import|
                _collect import  
              }
            end
          }
        end
      elsif bundle.is_a?(Buildr::Project)
        @projects << bundle
      end
    end
    
  end
  
  class DependenciesTask < Rake::Task #:nodoc:
    include BundleCollector
    attr_accessor :project

    def initialize(*args) #:nodoc:
      super

      enhance do |task|
        _dependencies = {}
        _projects = {}
        project.projects.each do |subp|
          collect(subp)
          _projects[subp.name] = projects.collect {|p| p.name}.uniq.sort
          _dependencies[subp.name] = bundles.collect {|b| b.to_s }.uniq.sort 
        end
        
        collect(project)
        _dependencies[project.name] = bundles.collect {|b| b.to_s }.uniq.sort 
        _projects[project.name] = projects.collect {|p| p.name}.uniq.sort
        
        dependencies = ::OSGi::Dependencies.new(project)
        dependencies.write(_projects.keys) {|hash, p|
          unless _dependencies[p].nil?
            hash[p]["dependencies"] = _dependencies[p]
          end
          unless _projects[p].nil?
            hash[p]["projects"] = _projects[p]
          end
        }
      end
    end
  end

  class InstallBundlesTask < Rake::Task #:nodoc:
    attr_accessor :project
    def initialize(*args) #:nodoc:
      super
      enhance do |task|
        puts "Deploy directory: #{OSGi.registry.release_to}/plugins"
        mkpath "#{OSGi.registry.release_to}/plugins"
        project.projects.each do |subp|
          subp.packages.select {|package| package.is_a?(::OSGi::BundlePackaging)}.each do |package|
            puts "Deploying #{subp.artifact(package)} to #{OSGi.registry.release_to}"
            cp(subp.artifact(package).to_s, "#{OSGi.registry.release_to}/plugins") 
          end
        end
      end
    end
  end
  
  class InstallTask < Rake::Task #:nodoc:
    include BundleCollector
    attr_accessor :project, :local

    def initialize(*args) #:nodoc:
      super

      enhance do |task|
        dependencies = []
        project.projects.each do |subp|
          collect(subp)
          dependencies |= bundles
        end
        collect(project)
        dependencies |= bundles
        dependencies.flatten.uniq.sort.each {|bundle|
          
          begin
            if File.directory?(bundle.file)
              begin
               
                tmp = File.join(Dir::tmpdir, File.basename(bundle.file))
                rm tmp if File.exists? tmp
                base = Pathname.new(bundle.file)
                Zip::ZipFile.open(tmp, Zip::ZipFile::CREATE) {|zipfile|
                  Dir.glob("#{bundle.file}/**/**").each do |file|
                    if(file.match(/.*\.jar/)) #unpack the jars in the directory so its contents are readable by all Java compilers.
                      Zip::ZipFile.open(file) do |source|
                        source.entries.reject { |entry| entry.directory? }.each do |entry|
                          zipfile.get_output_stream(entry.name) {|output| output.write source.read(entry.name)}
                        end
                      end
                    else
                      zipfile.add(Pathname.new(file).relative_path_from(base), file)
                    end
                  end
                }
                bundle.file = tmp
                
              rescue Exception => e
                error e.message
                trace e.backtrace.join("\n")
              end
              
            end
            
            if local
              artifact = Buildr::artifact(bundle.to_s)
              installed = Buildr.repositories.locate(artifact)
              rm_rf installed
              mkpath File.dirname(installed)
              Buildr::artifact(bundle.to_s).from(bundle.file).install
              info "Installed #{installed}"
            else
              Buildr::artifact(bundle.to_s).from(bundle.file).upload
              info "Uploaded #{bundle}"
            end
          rescue Exception => e
            error "Error installing the artifact #{bundle.to_s}"
            trace e.message
            trace e.backtrace.join("\n")
          end
        }
      end
    end
  end
  
  module ProjectExtension #:nodoc:
    include Extension

    first_time do
      desc 'Evaluate OSGi dependencies and places them in dependencies.yml'
      Project.local_task('osgi:resolve:dependencies') { |name| "Resolve dependencies for #{name}" }
      desc 'Installs OSGi dependencies in the Maven local repository'
      Project.local_task('osgi:install:dependencies') { |name| "Install dependencies for #{name}" }
      desc 'Installs OSGi dependencies in the Maven local repository'
      Project.local_task('osgi:upload:dependencies') { |name| "Upload dependencies for #{name}" }
      desc 'Cleans the dependencies.yml file'
      Project.local_task('osgi:clean:dependencies') {|name| "Clean dependencies for #{name}"}
      desc 'Installs the bundle projects into an OSGi repository'
      Project.local_task('osgi:install:bundles') {|name| "Install bundles for #{name}"}
    end

    before_define do |project|
      dependencies = DependenciesTask.define_task('osgi:resolve:dependencies')
      dependencies.project = project
      install = InstallTask.define_task('osgi:install:dependencies')
      install.project = project
      install.local = true
      upload = InstallTask.define_task('osgi:upload:dependencies')
      upload.project = project
      
      
      clean = Rake::Task.define_task('osgi:clean:dependencies').enhance do
        Buildr::write File.join(project.base_dir, "dependencies.yml"), 
          project.projects.inject({}) {|hash, p| hash.merge({p.name => {}})}.merge({project.name => {}}).to_yaml
      end

      install_bundles = InstallBundlesTask.define_task('osgi:install:bundles')
      install_bundles.project = project
    end

    #
    # 
    # Reads the dependencies from dependencies.yml
    # and returns the direct dependencies of the project, as well as its project dependencies and their own dependencies.
    # This method is used recursively, so beware of cyclic dependencies.
    #
    def dependencies(&block)
      deps = ::OSGi::Dependencies.new(project)
      deps.read
      deps.dependencies + deps.projects
    end
    
    # returns an array of the dependencies of the plugin, read from the manifest.
    def manifest_dependencies()
      as_bundle = Bundle.fromProject(self)
      as_bundle.nil? ? [] : as_bundle.bundles.collect{|b| b.resolve}.compact + as_bundle.imports.collect {|i| i.resolve}.flatten
    end
    
    # Returns the EE defined in the manifest if present.
    def execution_environments()   
      # Code copied straight from Bundle.fromProject
      packaging = project.packages.select {|package| package.is_a?(BundlePackaging)}
      raise "More than one bundle packaging is defined over the project #{project.id}, see BOSGI-16." if packaging.size > 1
      m = ::Buildr::Packaging::Java::Manifest.new(File.exists?(project.path_to("META-INF/MANIFEST.MF")) ? File.read(project.path_to("META-INF/MANIFEST.MF")) : nil)
      m.main.merge!(packaging.first.manifest) unless packaging.empty? 
      (Manifest.read(m.to_s).first["Bundle-RequiredExecutionEnvironment"] || {}).keys.compact.flatten.collect {|ee| OSGi.options.available_ee[ee]}
    end
    
  end
  
end

module Buildr #:nodoc:
  class Project #:nodoc:
    include OSGi::ProjectExtension
  end
end
