# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require "open-uri"
require "time"

class PackageTask
  include Rake::DSL

  def initialize(package, version, release_time)
    @package = package
    @version = version
    @release_time = release_time

    @archive_base_name = "#{@package}-#{@version}"
    @archive_name = "#{@archive_base_name}.tar.gz"
    @full_archive_name = File.expand_path(@archive_name)

    @rpm_package = @package
  end

  def define
    define_dist_task
    define_yum_task
    define_apt_task
    define_version_task
  end

  private
  def env_value(name)
    value = ENV[name]
    raise "Specify #{name} environment variable" if value.nil?
    value
  end

  def parallel_build?
    ENV["PARALLEL"] == "yes"
  end

  def latest_commit_time(git_directory)
    cd(git_directory) do
      return Time.iso8601(`git log -n 1 --format=%aI`.chomp).utc
    end
  end

  def run_vagrant(id)
    sh("vagrant", "up", id)
    sh("vagrant", "destroy", "--force", id)
  end

  def define_dist_task
    define_archive_task
    desc "Create release package"
    task :dist => [@archive_name]
  end

  def define_yum_task
    namespace :yum do
      distribution = "centos"
      yum_dir = "yum"
      repositories_dir = "#{yum_dir}/repositories"

      directory repositories_dir

      desc "Build RPM packages"
      task :build => [@archive_name, repositories_dir] do
        tmp_dir = "#{yum_dir}/tmp"
        rm_rf(tmp_dir)
        mkdir_p(tmp_dir)
        cp(@archive_name, tmp_dir)

        env_sh = "#{yum_dir}/env.sh"
        File.open(env_sh, "w") do |file|
          file.puts(<<-ENV)
SOURCE_ARCHIVE=#{@archive_name}
PACKAGE=#{@rpm_package}
VERSION=#{@version}
DEPENDED_PACKAGES="#{rpm_depended_packages.join("\n")}"
          ENV
        end

        tmp_distribution_dir = "#{tmp_dir}/#{distribution}"
        mkdir_p(tmp_distribution_dir)
        spec = "#{tmp_distribution_dir}/#{@rpm_package}.spec"
        spec_in = "#{yum_dir}/#{@rpm_package}.spec.in"
        spec_in_data = File.read(spec_in)
        spec_data = spec_in_data.gsub(/@(.+?)@/) do |matched|
          case $1
          when "PACKAGE"
            @rpm_package
          when "VERSION"
            @version
          else
            matched
          end
        end
        File.open(spec, "w") do |spec_file|
          spec_file.print(spec_data)
        end

        cd(yum_dir) do
          sh("vagrant", "destroy", "--force")
          distribution_versions = {
            "6" => ["x86_64"],
            "7" => ["x86_64"],
          }
          threads = []
          distribution_versions.each do |ver, archs|
            archs.each do |arch|
              id = "#{distribution}-#{ver}-#{arch}"
              if parallel_build?
                threads << Thread.new(id) do |local_id|
                  run_vagrant(local_id)
                end
              else
                run_vagrant(id)
              end
            end
          end
          threads.each(&:join)
        end
      end
    end

    desc "Release Yum packages"
    yum_tasks = [
      "yum:build",
    ]
    task :yum => yum_tasks
  end

  def define_apt_task
    namespace :apt do
      code_names = [
        ["debian", "stretch"],
        ["ubuntu", "16.04"],
        ["ubuntu", "17.04"],
      ]
      architectures = [
        "i386",
        "amd64",
      ]
      debian_dir = "debian"
      apt_dir = "apt"
      repositories_dir = "#{apt_dir}/repositories"

      directory repositories_dir

      desc "Build DEB packages"
      task :build => [@archive_name, repositories_dir] do
        tmp_dir = "#{apt_dir}/tmp"
        rm_rf(tmp_dir)
        mkdir_p(tmp_dir)
        cp(@archive_name, tmp_dir)
        cp_r(debian_dir, "#{tmp_dir}/debian")

        env_sh = "#{apt_dir}/env.sh"
        File.open(env_sh, "w") do |file|
          file.puts(<<-ENV)
PACKAGE=#{@package}
VERSION=#{@version}
DEPENDED_PACKAGES="#{deb_depended_packages.join("\n")}"
          ENV
        end

        cd(apt_dir) do
          sh("vagrant", "destroy", "--force")
          threads = []
          code_names.each do |distribution, code_name|
            architectures.each do |arch|
              if arch == "i386"
                next unless code_name == "17.04"
              end
              id = "#{distribution}-#{code_name}-#{arch}"
              if parallel_build?
                threads << Thread.new(id) do |local_id|
                  run_vagrant(local_id)
                end
              else
                run_vagrant(id)
              end
            end
          end
          threads.each(&:join)
        end
      end
    end

    desc "Release APT repositories"
    apt_tasks = [
      "apt:build",
    ]
    task :apt => apt_tasks
  end

  def define_version_task
    namespace :version do
      desc "Update versions"
      task :update do
        update_debian_changelog
        update_spec
      end
    end
  end

  def package_version
    "#{@version}-1"
  end

  def package_changelog_message
    "New upstream release."
  end

  def packager_name
    ENV["DEBFULLNAME"] || ENV["NAME"] || `git config --get user.name`.chomp
  end

  def packager_email
    ENV["DEBEMAIL"] || ENV["EMAIL"] || `git config --get user.email`.chomp
  end

  def update_content(path)
    if File.exist?(path)
      content = File.read(path)
    else
      content = ""
    end
    content = yield(content)
    File.open(path, "w") do |file|
      file.puts(content)
    end
  end

  def update_debian_changelog
    update_content("debian/changelog") do |content|
      <<-CHANGELOG.rstrip
#{@package} (#{package_version}) unstable; urgency=low

  * New upstream release.

 -- #{packager_name} <#{packager_email}>  #{@release_time.rfc2822}

#{content}
      CHANGELOG
    end
  end

  def update_spec
    release_time = @release_time.strftime("%a %b %d %Y")
    update_content("yum/#{@rpm_package}.spec.in") do |content|
      content = content.sub(/^(%changelog\n)/, <<-CHANGELOG)
%changelog
* #{release_time} #{packager_name} <#{packager_email}> - #{package_version}
- #{package_changelog_message}

      CHANGELOG
      content = content.sub(/^(Release:\s+)\d+/, "\\11")
      content.rstrip
    end
  end
end
