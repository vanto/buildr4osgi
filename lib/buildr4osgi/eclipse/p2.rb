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

module Buildr4OSGi

  module P2

    include Extension

    def package_as_p2_from_site(file_name)
      task = UpdateSitePublisherTask.define_task(file_name)
      task.send :associate_with, self
      task
    end
    
    def package_as_p2_from_site_spec(spec)
      spec.merge(:type => :zip, :classifier => "p2", :id => name.split(":").last)
    end

    class UpdateSitePublisherTask < ::Buildr::Packaging::Java::JarTask

      attr_accessor :site
      
      def initialize(*args) #:nodoc:
        super
        
        enhance do |p2_task|
          fail "The p2 task needs to be associated with a site " unless site
          p2_task.enhance [site]
          #add a prerequisite to the list of prerequisites, gives a chance
          #for other prerequisites to be placed before this block is executed.
          p2_task.enhance do 
            targetP2Repo = File.join(project.base_dir, "target", "p2repository")
            mkpath targetP2Repo
            Buildr::unzip(targetP2Repo=>project.package(:site).to_s).extract
            eclipseSDK = Buildr::artifact("org.eclipse:eclipse-SDK:zip:3.6M3-win32")
            eclipseSDK.invoke
            Buildr::unzip(File.dirname(eclipseSDK.to_s) => eclipseSDK.to_s).extract

            launcherPlugin = Dir.glob("#{File.dirname(eclipseSDK.to_s)}/eclipse/plugins/org.eclipse.equinox.launcher_*")[0]

            cmdline <<-CMD
            java -jar #{launcherPlugin} -application org.eclipse.equinox.p2.publisher.UpdateSitePublisher
            -metadataRepository file:#{targetP2Repo} 
            -artifactRepository file:#{targetP2Repo}
            -metadataRepositoryName #{project.name}_#{project.version}
            -artifactRepositoryName #{project.name}_#{project.version} 
            -source #{targetP2Repo} 
            -configs gtk.linux.x86 
            -publishArtifacts 
            -clean -consoleLog
            CMD
            info "Invoking P2's metadata generation: #{cmdline}"
            system cmdline

            include targetP2Repo, :as => "."
          end
        end
      end

      # :call-seq:
      #   with(options) => self
      #
      # Passes options to the task and returns self. 
      #
      def with(options)
        options.each do |key, value|
          begin
            send "#{key}=", value
          rescue NoMethodError
            raise ArgumentError, "#{self.class.name} does not support the option #{key}"
          end
        end
        self
      end

      private 

      attr_reader :project
      
      def associate_with(project)
        @project = project
      end

    end
  end
end

class Buildr::Project
  include Buildr4OSGi::P2
end

