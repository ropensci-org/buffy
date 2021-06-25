require 'airrecord'

module Ropensci
  class AirtableWorker < BuffyWorker

    attr_accessor :params, :airtable_config

    def perform(action, config, locals, params)
      load_context_and_env(locals)
      @params = OpenStruct.new(params)
      @airtable_config = { api_key: buffy_settings['env']['airtable_api_key'],
                           base_id: buffy_settings['env']['airtable_base_id'] }
      case action.to_sym
      when :assign_reviewer
        assign_reviewer
      when :remove_reviewer
        remove_reviewer
      end
    end

    def assign_reviewer
      reviewer = user_login(params.reviewer.to_s)
      begin
        gh_user = Octokit.user(reviewer)
      rescue Octokit::NotFound
        respond("I could not find user @#{reviewer}") and return
      end

      if gh_user
        # Check if reviewer present in Airtable reviewers-prod or create it
        reviewer_entry = airtable_revs.all(filter: "{github} = '#{gh_user.login}'").first ||
                            airtable_revs.create(github: gh_user.login, name: gh_user.name, email: gh_user.email)

        # Add current_assignment to reviewers
        reviewer_entry["current_assignment"] = "https://github.com/#{context.repo}/#{context.issue_id}"
        reviewer_entry.save

        # Add entry in the **reviews** airtable
        airtable_reviews.create(id_no: "#{context.issue_id}",
                       github: [reviewer_entry.id],
                       onboarding_url: reviewer_entry["current_assignment"],
                       package: params.package_name)

        # Respond to GH with:
        respond("@#{gh_user.login}: If you haven't done so, please fill [this form](https://airtable.com/shrnfDI2S9uuyxtDw) for us to update our reviewers records.")
      end
    end

    def remove_reviewer
      reviewer = user_login(params.reviewer.to_s)

      # Delete current assignment
      reviewer_entry = airtable_revs.all(filter: "{github} = '#{reviewer}'").first
      if reviewer_entry
        reviewer_entry["current_assignment"] = ""
        reviewer_entry.save
      end

      # Delete review entry
      review_entry = airtable_reviews.all(filter: "{github} = '#{reviewer}' AND {id_no} = '#{context.issue_id}'").first
      if review_entry
        review_entry.destroy
      end
    end

    private

    def airtable_revs
      @airtable_reviewers_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "reviewers-prod")
    end

    def airtable_reviews
      @airtable_reviews_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "reviews")
    end
  end
end
