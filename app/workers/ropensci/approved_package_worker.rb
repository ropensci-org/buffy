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
      when :invite_author_to_transfered_repo
        invite_author_to_transfered_repo
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
      org_team_name = "#{params.package_name}"
      org_team_name = "ropensci/#{org_team_name}" unless org_team_name.start_with?("ropensci/")

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
            respond("Transfer completed. \nThe `#{params.package_name}` team is now owner of [the repository](https://github.com/#{org_team_name}) and the author has been invited to the team")
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

    def invite_author_to_transfered_repo
      org_team_name = "#{params.package_name}"
      org_team_name = "ropensci/#{org_team_name}" unless org_team_name.start_with?("ropensci/")

      if github_client.repository?(org_team_name)
        if invite_user_to_team(params.package_author, org_team_name)
          respond("Invitation sent!")
        else
          respond("Can't send invitation: There's not a `#{org_team_name}` team")
        end
      else
        respond("Can't find repository `#{org_team_name}`, have you forgotten to transfer it first?")
      end
    end
  end
end
