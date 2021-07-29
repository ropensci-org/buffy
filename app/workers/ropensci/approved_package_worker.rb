require 'airrecord'

module Ropensci
  class ApprovedPackageWorker < BuffyWorker

    attr_accessor :params

    def perform(action, config, locals, params)
      load_context_and_env(locals)
      @params = OpenStruct.new(params)

      case action.to_sym
      when :new_team
        new_team
      end
    end

    def new_team
      user_to_invite = context.issue_author.to_s.strip
      team_name = params.team_name.to_s.strip

      unless user_to_invite.empty? || team_name.empty?
        invite_user_to_team(user_to_invite, "ropensci/#{team_name}")
      end
    end
  end
end
