require "airrecord"
require "date"

module Ropensci
  class AirtableWorker < BuffyWorker

    attr_accessor :params, :airtable_config

    def perform(action, config, locals, params)
      load_context_and_env(locals)
      @params = OpenStruct.new(params)
      @airtable_config = { api_key: buffy_settings["env"]["airtable_api_key"],
                           base_id: buffy_settings["env"]["airtable_base_id"] }
      case action.to_sym
      when :assign_reviewer
        assign_reviewer
      when :remove_reviewer
        remove_reviewer
      when :submit_review
        submit_review(config)
      when :submit_author_response
        submit_author_response
      when :slack_invites
        slack_invites
      when :clear_assignments
        clear_assignments
      when :package_and_authors
        package_and_authors
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
        package_entry = airtable_packages.all(filter: "{package-name} = '#{params.package_name}'").first

        review_entry["review_url"] = params.review_url
        review_entry["review_hours"] = params.review_time
        review_entry["review_date"] = Date.parse(params.review_date).strftime("%Y-%m-%d")
        review_entry["packages"] = [package_entry.id] if package_entry
        review_entry.save

        respond("Logged review for _#{reviewer}_ (hours: #{params.review_time})")

        reviewers = params.reviewers.to_s.split(",").map{|r| user_login(r.strip)}

        add_labels = config["label_when_all_reviews_in"]
        add_labels = [add_labels] unless add_labels.is_a?(Array)
        add_labels = add_labels.uniq.compact

        remove_labels = config["unlabel_when_all_reviews_in"]
        remove_labels = [remove_labels] unless remove_labels.is_a?(Array)
        remove_labels = remove_labels.uniq.compact

        unless reviewers.empty? || [add_labels, remove_labels].flatten.empty?
          reviewers_filter = reviewers.inject([]){|_,r| _ << "{github} = '#{r}'"}
          reviewers_condition = reviewers_filter.join(", ")
          filter = "AND(OR(#{reviewers_condition}), {id_no} = '#{context.issue_id}')"
          current_reviews = airtable_reviews.all(filter: filter)
          finished_reviews_count = current_reviews.count {|r| r["review_url"].to_s.strip != ""}

          if finished_reviews_count == reviewers.size
            label_issue(add_labels) unless add_labels.empty?

            set_reminder_for_authors_response(params.package_authors) unless params.package_authors.empty?

            unless remove_labels.empty?
              remove_labels.each {|label| unlabel_issue(label)}
            end
          end
        end
      else
        respond("Couldn't find entry for _#{reviewer}_ in the reviews log")
      end
    end

    def submit_author_response
      package_entry = airtable_packages.all(filter: "{package-name} = '#{params.package_name}'").first
      if package_entry
        airtable_author_responses.create(id_no: params.author_response_id,
                                         response_date: params.submitting_date,
                                         package: [package_entry.id],
                                         response_url: params.author_response_url)

        respond("Logged author response!")
      else
        respond("Couldn't find entry for _#{params.package_name}_ in the packages log")
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
                                      date: Time.now.strftime("%Y-%m-%d"),
                                      role: "author1")
      end

      reviewers.uniq.compact.each do |reviewer|
        airtable_slack_invites.create(package: params.package_name,
                                      name: name_or_github_login(reviewer),
                                      email: reviewer.email,
                                      github: "https://github.com/#{reviewer.login}",
                                      date: Time.now.strftime("%Y-%m-%d"),
                                      role: "reviewer")
      end

      author_others.uniq.compact.each do |other|
        airtable_slack_invites.create(package: params.package_name,
                                      name: name_or_github_login(other),
                                      email: other.email,
                                      github: "https://github.com/#{other.login}",
                                      date: Time.now.strftime("%Y-%m-%d"),
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

    def package_and_authors
      author1_entry = airtable_authors.all(filter: "{github} = '#{params.author1}'").first ||
                      airtable_authors.create(github: params.author1)

      author_others_entries = []
      params.author_others.each do |author_other|

        author_others_entries << (airtable_authors.all(filter: "{github} = '#{author_other}'").first ||
                                 airtable_authors.create(github: author_other))
      end

      package_entry = airtable_packages.all(filter: "{package-name} = '#{params.package_name}'").first
      unless package_entry
        airtable_packages.create("package-name" => params.package_name,
                                 "submission-url" => params.submission_url,
                                 "repo-url" => params.repo_url,
                                 "submission-date" => Date.parse(params.submitted_at).strftime("%Y-%m-%d"),
                                 "editor" => params.editor,
                                 "author1" => [author1_entry.id],
                                 "author-others" => author_others_entries.map(&:id))
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

    def airtable_authors
      @airtable_authors_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "authors")
    end

    def airtable_packages
      @airtable_packages_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "packages")
    end

    def airtable_author_responses
      @airtable_author_responses_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "author-responses")
    end

    def name_or_github_login(gh_user)
      if gh_user.name.nil? || gh_user.name.empty?
        return "#{gh_user.login} (GitHub username)"
      else
        return gh_user.name
      end
    end

    def set_reminder_for_authors_response(author_list)
      schedule_at = Time.now + (12 * 86400) # 12 days from now
      reminder_txt = "#{author_list.join(', ')}: please post your response with `@ropensci-review-bot submit response <url to issue comment>`.\n\nHere's the author guide for response. https://devguide.ropensci.org/authors-guide.html"

      reminder_locals = {"issue_id" => context.issue_id, "repo" => context.repo}

      AsyncMessageWorker.perform_at(schedule_at, reminder_locals, reminder_txt)
     end
  end
end
