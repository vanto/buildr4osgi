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
  module Compiler
    class OSGiC < Buildr::Compiler::Javac
      require "jdtc"
      include Jdtc
      
      OPTIONS = [:warnings, :debug, :deprecation, :source, :target, :lint, :other]
    
      specify :language=>:java, :sources => 'java', :source_ext => 'java',
              :target=>'classes', :target_ext=>'class', :packaging=>:plugin
              
              
      def compile(sources, target, dependencies) #:nodoc:
        check_options options, OPTIONS
        cmd_args = []
        # tools.jar contains the Java compiler.
        dependencies << Java.tools_jar if Java.tools_jar
        cmd_args << '-classpath' << dependencies.join(File::PATH_SEPARATOR) unless dependencies.empty?
        source_paths = sources.select { |source| File.directory?(source) }
        cmd_args << '-sourcepath' << source_paths.join(File::PATH_SEPARATOR) unless source_paths.empty?
        cmd_args << '-d' << File.expand_path(target)
        cmd_args += javac_args
        cmd_args += files_from_sources(sources)
        unless Buildr.application.options.dryrun
          trace((['osgic'] + cmd_args).join(' '))
          jdtc(cmd_args)
        end
      end
      alias :osgic_args :javac_args 
    end
    
  end
end

Buildr::Compiler.compilers.unshift Buildr4OSGi::Compiler::OSGiC