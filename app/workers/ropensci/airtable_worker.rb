require 'airrecord'

module Ropensci
  class AirtableWorker < BuffyWorker

    def perform(action, config, locals, params)
      load_context_and_env(locals)
      @params = params
      @airtable_api_key = buffy_settings['env']['airtable_api_key']
      @airtable_base_id = buffy_settings['env']['airtable_base_id']
      case action.to_sym
      when :assign_reviewer
        assign_reviewer
      end
    end

    def assign_reviewer
      reviewer = user_login(@params["reviewer"])
      begin
        gh_user = Octokit.user(reviewer)
      rescue Octokit::NotFound
        respond("I could not find user @#{reviewer}") and return
      end

      # Declare Airtable's Tables
      airtable_revs = Airrecord.table(@airtable_api_key, @airtable_base_id, "reviewers-prod")
      airtable_reviews = Airrecord.table(@airtable_api_key, @airtable_base_id, "reviews")

      # Check if reviewer present in Airtable reviewers-prod or create it
      airtable_reviewer = airtable_revs.all(filter: "{github} = '#{gh_user.login}'").first ||
                          airtable_revs.create(github: gh_user.login, name: gh_user.name, email: gh_user.email)

      # Add current_assignment to reviewers
      airtable_reviewer["current_assignment"] = "https://github.com/#{context.repo}/#{context.issue_id}"
      airtable_reviewer.save

      #Add entry in the **reviews** airtable
      airtable_reviews.create(id_no: "#{context.issue_id}",
                     github: [airtable_reviewer.id],
                     onboarding_url: airtable_reviewer["current_assignment"],
                     package: @params["package_name"])

      #Respond to GH with:
      respond("@#{gh_user.login}: If you haven't done so, please fill [this form](https://airtable.com/shrnfDI2S9uuyxtDw) for us to update our reviewers records.")
    end
  end
end
