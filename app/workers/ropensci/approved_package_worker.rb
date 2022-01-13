module Ropensci
  class ApprovedPackageWorker < BuffyWorker

    attr_accessor :params

    def perform(action, config, locals, params)
      load_context_and_env(locals)
      @params = OpenStruct.new(params)

      case action.to_sym
      when :new_team
        new_team
      when :finalize_transfer
        finalize_transfer
      end
    end

    def new_team
      user_to_invite = context.issue_author.to_s.strip
      team_name = params.team_name.to_s.strip

      unless user_to_invite.empty? || team_name.empty?
        invite_user_to_team(user_to_invite, "ropensci/#{team_name}")
      end
    end

    def finalize_transfer
      org_team_name = "ropensci/#{params.package_name}"

      if github_client.repository?(org_team_name)
        package_team_id = api_team_id(org_team_name)

        if package_team_id.nil?
          package_team = add_new_team(org_team_name)
          package_team_id = package_team.id if package_team
        end

        invite_user_to_team(params.package_author, org_team_name) if package_team_id

        if package_team_id
          url = "https://api.github.com/orgs/ropensci/teams/#{params.package_name}/repos/ropensci/#{params.package_name}"
          parameters = { permission: "admin" }
          response = Faraday.put(url, parameters.to_json, github_headers)
          if response.status.between?(200, 299)
            respond("Transfer completed. The `#{params.package_name}` team is now owner of [the repository](https://github.com/#{org_team_name})")
          else
            respond("Could not finalize transfer: Could not add owner rights to the `#{params.package_name}` team")
          end
        else
          respond("Could not finalize transfer: Error creating the `#{org_team_name}` team")
        end
      else
        respond("Can't find repository `#{org_team_name}`, have you forgotten to transfer it first?")
      end

    end
  end
end
