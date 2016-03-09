# -*- encoding: utf-8 -*-
#
# Author:: Andrei Skopenko (<andrei@skopenko.net>)
#
# Copyright 2015 Andrei Skopenko
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen/provisioner/policyfile_zero'
require 'kitchen/provisioner/base'
require 'kitchen/transport/ssh'

# continue loading if kitchen-sync not installed
begin
  require 'kitchen/transport/sftp'
rescue LoadError
  puts 'Ignoring sftp transport...'
end

module Kitchen
  module Transport
    class Sftp
      class Connection
        # Execute a remote command over SFTP and return the command's exit code and output.
        #
        # @param command [String] command string to execute
        # @return [Hash] the exit code and output of the command
        def execute_with_output_and_exit_code(command)
          exit_code = nil
          output = ''
          session.open_channel do |channel|
            channel.request_pty

            channel.exec(command) do |_ch, _success|
              channel.on_data do |_ch, data|
                output << data
              end

              channel.on_extended_data do |_ch, _type, data|
                output << data
              end

              channel.on_request('exit-status') do |_ch, data|
                exit_code = data.read_long
              end
            end
          end
          session.loop { exit_code.nil? }
          [exit_code, output]
        end
      end
    end

    class Ssh
      class Connection
        # Execute a remote command over SSH and return the command's exit code and output.
        #
        # @param command [String] command string to execute
        # @return [Hash] the exit code and output of the command
        def execute_with_output_and_exit_code(command)
          exit_code = nil
          output = ''
          session.open_channel do |channel|
            channel.request_pty

            channel.exec(command) do |_ch, _success|
              channel.on_data do |_ch, data|
                output << data
              end

              channel.on_extended_data do |_ch, _type, data|
                output << data
              end

              channel.on_request('exit-status') do |_ch, data|
                exit_code = data.read_long
              end
            end
          end
          session.loop { exit_code.nil? }
          [exit_code, output]
        end

        # Execute command over SSH and return the command's output.
        #
        # @param command [String] command string to execute
        # @return [String] the output of the executed command
        def execute_with_output(command)
          return if command.nil?
          logger.debug("[SSH] #{self} (#{command})")
          exit_code, output = execute_with_output_and_exit_code(command)

          if exit_code != 0
            raise Transport::SshFailed,
              "SSH exited (#{exit_code}) for command: [#{command}]"
          end
          output
        rescue Net::SSH::Exception => ex
          raise SshFailed, "SSH command failed (#{ex.message})"
        end
      end
    end
  end
end

module Kitchen
  module Provisioner
    class Base
      # PolicyfileNodes needs to access to provision of the instance
      # without invoking the behavior of Base#call because we need to
      # add additional command after chef_client run complete.
      #
      # @param state [Hash] mutable instance state
      # @raise [ActionFailed] if the action could not be completed
      def call(state)
        create_sandbox
        sandbox_dirs = Dir.glob(File.join(sandbox_path, '*'))

        instance.transport.connection(state) do |conn|
          conn.execute(install_command)
          conn.execute(init_command)
          info("Transferring files to #{instance.to_str}")
          conn.upload(sandbox_dirs, config[:root_path])
          debug('Transfer complete')
          conn.execute(prepare_command)
          conn.execute(run_command)
          # Get node json object generated by chef_client
          output = conn.execute_with_output(dump_command)
          File.open(ext_node_file, 'w') { |f| f << output }
        end
      rescue Kitchen::Transport::TransportFailed => ex
        raise ActionFailed, ex.message
      ensure
        cleanup_sandbox
      end
    end

    class PolicyfileZero
      # PolicyfileNodes needs to access the base behavior of creating the
      # sandbox directory without invoking the behavior of
      # PolicyfileZero#create_sandbox, we need to override json node.
      alias create_policyfile_sandbox create_sandbox
    end

    class PolicyfileNodes < PolicyfileZero
      # (see PolicyfileZero#create_sandbox)
      def create_sandbox
        FileUtils.rm(ext_node_file) if File.exist?(ext_node_file)
        create_policyfile_sandbox
      end

      def ext_node_file
        File.join(config[:nodes_path], "#{instance.name}.json")
      end

      def int_node_file
        File.join(config[:root_path], 'nodes', "#{instance.name}.json")
      end

      def dump_command
        "sh -c 'cat #{int_node_file}'"
      end
    end
  end
end
