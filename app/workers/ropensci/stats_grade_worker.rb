module Ropensci
  class StatsGradesWorker < BuffyWorker

    attr_accessor :params

    def perform(action, locals, params)
      load_context_and_env(locals)
      @params = OpenStruct.new(params)

      case action.to_sym
      when :label
        label
      end
    end

    def label
      parameters = { repo: context[:repo], issue_num: context[:issue_id] }
      url = params.stats_badge_url || "http://138.68.123.59:8000/stats_badge"
      headers = {}

      response = Faraday.get(url, parameters, headers)

      if response.status.between?(200, 299)
        parsed = JSON.parse(response.body)
        label = parsed.is_a?(Array) ? parsed[0] : parsed

        label_issue([label])
      else
        logger.warn("Error: The stats badge service failed with response #{response.status} (called #{url} for #{context[:repo]} issue #{context[:issue_id]})")
      end
    end
  end
end
