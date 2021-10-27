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
      when :submit_review
        submit_review(config)
      when :slack_invites
        slack_invites
      when :clear_assignments
        clear_assignments
      end
    end

    def assign_reviewer
      reviewer = user_login(params.reviewer.to_s)
      gh_user = get_user(reviewer)
      if gh_user.nil?
        respond("I could not find user @#{reviewer}") and return
      end

      if gh_user
        # Check if reviewer present in Airtable reviewers-prod or create it
        reviewer_entry = airtable_revs.all(filter: "{github} = '#{gh_user.login}'").first ||
                            airtable_revs.create(github: gh_user.login, name: gh_user.name, email: gh_user.email)

        # Add current_assignment to reviewers
        reviewer_entry["current_assignment"] = issue_url
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
      review_entry = airtable_reviews.all(filter: "AND({github} = '#{reviewer}', {id_no} = '#{context.issue_id}')").first
      if review_entry
        review_entry.destroy
      end
    end

    def submit_review(config)
      reviewer = user_login(params.reviewer.to_s)
      review_entry = airtable_reviews.all(filter: "AND({github} = '#{reviewer}', {id_no} = '#{context.issue_id}')").first
      if review_entry
        review_entry["review_url"] = params.review_url
        review_entry["review_hours"] = params.review_time
        review_entry["review_date"] = params.review_date.strftime("%m/%d/%Y")
        review_entry.save

        respond("Logged review for _#{reviewer}_ (hours: #{params.review_time})")

        reviewers = params.reviewers.to_s.split(",").map{|r| user_login(r.strip)}
        unless reviewers.empty? || config['all_reviews_label'].to_s.strip.empty?
          reviewers_filter = reviewers.inject([]){|_,r| _ << "{github} = '#{r}'"}
          reviewers_condition = reviewers_filter.join(", ")
          filter = "AND(OR(#{reviewers_condition}), {id_no} = '#{context.issue_id}')"
          current_reviews = airtable_reviews.all(filter: filter)
          finished_reviews_count = current_reviews.count {|r| r["review_url"].to_s.strip != ""}

          label_issue([config["all_reviews_label"]].flatten) if finished_reviews_count == reviewers.size
        end
      else
        respond("Couldn't find entry for _#{reviewer}_ in the reviews log")
      end
    end

    def slack_invites
      author = get_user(params.author)

      reviewers = []
      params.reviewers.each do |reviewer|
        reviewers << get_user(reviewer)
      end

      author_others = []
      params.author_others.each do |other|
        author_others << get_user(other)
      end

      if author
        airtable_slack_invites.create(package: params.package_name,
                                      name: name_or_github_login(author),
                                      email: author.email,
                                      github: "https://github.com/#{author.login}",
                                      date: Time.now.strftime("%m/%d/%Y"),
                                      role: "author1")
      end

      reviewers.uniq.compact.each do |reviewer|
        airtable_slack_invites.create(package: params.package_name,
                                      name: name_or_github_login(reviewer),
                                      email: reviewer.email,
                                      github: "https://github.com/#{reviewer.login}",
                                      date: Time.now.strftime("%m/%d/%Y"),
                                      role: "reviewer")
      end

      author_others.uniq.compact.each do |other|
        airtable_slack_invites.create(package: params.package_name,
                                      name: name_or_github_login(other),
                                      email: other.email,
                                      github: "https://github.com/#{other.login}",
                                      date: Time.now.strftime("%m/%d/%Y"),
                                      role: "author-others")
      end
    end

    def clear_assignments
      params.reviewers.each do |reviewer|
        reviewer = user_login(reviewer.to_s)

        # Delete current assignment
        reviewer_entry = airtable_revs.all(filter: "{github} = '#{reviewer}'").first
        if reviewer_entry
          reviewer_entry["current_assignment"] = ""
          reviewer_entry.save
        end
      end
    end

    private

    def airtable_revs
      @airtable_reviewers_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "reviewers-prod")
    end

    def airtable_reviews
      @airtable_reviews_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "reviews")
    end

    def airtable_slack_invites
      @airtable_slack_invites_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "slack-invites")
    end

    def name_or_github_login(gh_user)
      if gh_user.name.nil? || gh_user.name.empty?
        return "#{gh_user.login} (GitHub username)"
      else
        return gh_user.name
      end
    end
  end
end
