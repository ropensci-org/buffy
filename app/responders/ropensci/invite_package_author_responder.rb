module Ropensci
  class InvitePackageAuthorResponder < Responder

    keyname :ropensci_invite_author

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{bot_name} invite me to ([\/\w-]+)?\.?\s*\z/i
    end

    def process_message(message)
      return unless verify_package
      Ropensci::ApprovedPackageWorker.perform_async("invite_author_to_transfered_repo", serializable(params), serializable(locals), serializable({ package_name: @package_name, package_author: @package_author }))
    end

    def verify_package
      @package_name = match_data[1].to_s.strip
      if @package_name.empty?
        respond("Could not invite: Please, specify the name of the team (should match the name of the package at the rOpenSci org)")
        return false
      end

      @package_author = context.issue_author.to_s.strip
      if @package_author != context.sender.to_s.strip
        respond("Could not invite, you are not the author of the package")
        return false
      end
      true
    end

    def default_description
      "Invite the author of a package to the corresponding rOpenSci team. This command should be issued by the author of the package."
    end

    def default_example_invocation
      "@#{@bot_name} invite me to ropensci/package-name"
    end
  end
end
