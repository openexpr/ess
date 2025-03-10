require("msgpack")
require("open3")
require("pathname")

require("enterprise_script_service/engine_error")
require("enterprise_script_service/message_processor")
require("enterprise_script_service/protocol")
require("enterprise_script_service/result")
require("enterprise_script_service/runner")
require("enterprise_script_service/service_channel")
require("enterprise_script_service/service_process")
require("enterprise_script_service/spawner")
require("enterprise_script_service/stat")

module EnterpriseScriptService
  SETUP_CODE = <<~'RUBY'
      def puts(*args)
        @stdout_buffer ||= ""
        args.each do |arg|
          @stdout_buffer << "#{arg}\n"
        end
        nil
      end

      def print(*args)
        @stdout_buffer ||= ""
        args.each do |arg|
          @stdout_buffer << arg.to_s
        end
        nil
      end
    RUBY

  class << self
    def run(input:, sources:, instructions: nil, timeout: 1, instruction_quota: 100000, instruction_quota_start: 0, memory_quota: 8 << 20)
      sources = [["setup", SETUP_CODE]] + sources

      packer = EnterpriseScriptService::Protocol.packer_factory.packer

      payload = {input: input, sources: sources}
      payload[:library] = instructions if instructions
      encoded = packer.pack(payload)

      packer = EnterpriseScriptService::Protocol.packer_factory.packer
      size = packer.pack(encoded.size)

      spawner = EnterpriseScriptService::Spawner.new
      service_process = EnterpriseScriptService::ServiceProcess.new(
        service_path,
        spawner,
        instruction_quota,
        instruction_quota_start,
        memory_quota,
      )
      runner = EnterpriseScriptService::Runner.new(
        timeout: timeout,
        service_process: service_process,
        message_processor_factory: EnterpriseScriptService::MessageProcessor,
      )
      runner.run(size, encoded)
    end

    private

    def service_path
      @service_path ||= begin
        base_path = Pathname.new(__dir__).parent
        base_path.join("bin/enterprise_script_service".freeze).to_s
      end
    end
  end
end
