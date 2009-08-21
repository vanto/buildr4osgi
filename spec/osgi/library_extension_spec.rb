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

require File.join(File.dirname(__FILE__), '../spec_helpers')

describe OSGi::BuildLibraries do
  
  it 'should merge with the jars of the libraries' do
    library_project(SLF4J, "group", "foo", "1.0.0")
    foo = project("foo")
    lambda {foo.package(:jar).invoke}.should_not raise_error
    jar = File.join(foo.base_dir, "target", "foo-1.0.0.jar")
    File.exists?(jar).should be_true
    Zip::ZipFile.open(jar) {|zip|
      zip.entries.size.should == 45
      zip.find_entry("org/slf4j/Marker.class").should_not be_nil  
    }
  end
  
  it 'should let users decide filters for exclusion when merging libraries' do
    library_project(SLF4J, "group", "foo", "1.0.0", :exclude => "org/slf4j/spi/*")
    foo = project("foo")
    lambda {foo.package(:jar).invoke}.should_not raise_error
    jar = File.join(foo.base_dir, "target", "foo-1.0.0.jar")
    File.exists?(jar).should be_true
    Zip::ZipFile.open(jar) {|zip|
      zip.find_entry("org/slf4j/spi/MDCAdapter.class").should be_nil  
      zip.find_entry("META-INF/maven/org.slf4j/slf4j-api").should_not be_nil  
    }
    library_project(SLF4J, "group", "bar", "1.0.0", :include => ["org/slf4j/spi/MarkerFactoryBinder.class", "META-INF/*"])
    bar = project("bar")
    lambda {bar.package(:jar).invoke}.should_not raise_error
    jar = File.join(bar.base_dir, "target", "bar-1.0.0.jar")
    File.exists?(jar).should be_true
    Zip::ZipFile.open(jar) {|zip|
      zip.find_entry("org/slf4j/spi/MDCAdapter.class").should be_nil  
      zip.find_entry("org/slf4j/spi/MarkerFactoryBinder.class").should_not be_nil  
      zip.find_entry("META-INF/maven/org.slf4j/slf4j-api").should_not be_nil  
    }
  end
  
  it 'should show the exported packages (the non-empty ones) under the Export-Package header in the manifest' do
    library_project(SLF4J, "group", "foo", "1.0.0")
    foo = project("foo")
    lambda {foo.package(:jar).invoke}.should_not raise_error
    jar = File.join(foo.base_dir, "target", "foo-1.0.0.jar")
    File.exists?(jar).should be_true
    Zip::ZipFile.open(jar) {|zip|
      manifest = zip.find_entry("META-INF/MANIFEST.MF")
      manifest.should_not be_nil  
      contents = Manifest.read(zip.read(manifest))
      contents.first["Export-Package"].should_not be_nil
      contents.first["Export-Package"].keys.should include("org.slf4j.helpers")
      contents.first["Export-Package"].keys.should_not include("org")
    }
  end
  
  it 'should produce a zip of the sources' do
    library_project(SLF4J, "group", "foo", "1.0.0")
    foo = project("foo")
    lambda {foo.package(:sources).invoke}.should_not raise_error
    sources = File.join(foo.base_dir, "target", "foo-1.0.0-sources.zip")
    File.exists?(sources).should be_true
    Zip::ZipFile.open(sources) {|zip|
      zip.find_entry("org/slf4j/Marker.java").should_not be_nil
    }
  end   
  
  it 'should warn when the source of a library is unavailable' do
    library_project(DEBUG_UI, "group", "foo", "1.0.0")
    lambda {project("foo").package(:sources).invoke}.should show_warning(/Could not find sources for/)    
  end
  
  it 'should raise an exception if passed a dependency it can\'t understand' do
    lambda {library_project(123, "group", "foo", "1.0.0")}.should raise_error(/Don't know how to interpret lib 123/)
  end
  
  
end