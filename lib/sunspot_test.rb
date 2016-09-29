require 'sunspot/rails'
require 'net/http'

module SunspotTest
  class TimeOutError < StandardError; end;
  class << self

    attr_writer :solr_startup_timeout
    attr_writer :server

    def solr_startup_timeout
      @solr_startup_timeout || 15
    end

    def setup_solr
      unstub
      start_sunspot_server
    end

    def server
      @server ||= Sunspot::Rails::Server.new
    end

    def start_sunspot_server
      unless solr_running?
        pid = fork do
          STDERR.reopen("/dev/null")
          STDOUT.reopen("/dev/null")
          server.run
        end

        at_exit { Process.kill("TERM", pid) }

        wait_until_solr_starts
      end
    end

    # Stubs Sunspot calls to Solr server
    def stub
      unless @session_stubbed
        Sunspot.session = Sunspot::Rails::StubSessionProxy.new(original_sunspot_session)
        @session_stubbed = true
      end
    end

    # Resets Sunspot to call Solr server, opposite of stub
    def unstub
      if @session_stubbed
        Sunspot.session = original_sunspot_session
        @session_stubbed = false
      end
    end

    private

    def original_sunspot_session
      @original_sunspot_session ||= Sunspot.session
    end

    def wait_until_solr_starts
      (solr_startup_timeout * 10).times do
        break if solr_running?
        sleep(0.1)
      end
      raise TimeOutError, "Solr failed to start after #{solr_startup_timeout} seconds" unless solr_running?
    end

    def solr_running?
      begin
        solr_ping_uri = URI.parse("#{Sunspot.session.config.solr.url}/admin/ping")
        res = Net::HTTP.get_response(solr_ping_uri)
        # Solr will return 503 codes when it's starting up
        res.code != '503'
      rescue
        false # Solr Not Running
      end
    end
  end
end
