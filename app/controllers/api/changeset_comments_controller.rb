module Api
  class ChangesetCommentsController < ApiController
    before_action :check_api_writable
    before_action :authorize

    authorize_resource

    before_action :require_public_data, :only => [:create]

    before_action :set_request_formats

    ##
    # Add a comment to a changeset
    def create
      # Check the arguments are sane
      raise OSM::APIBadUserInput, "No id was given" unless params[:id]
      raise OSM::APIBadUserInput, "No text was given" if params[:text].blank?
      raise OSM::APIRateLimitExceeded if rate_limit_exceeded?

      # Extract the arguments
      id = params[:id].to_i
      body = params[:text]

      # Find the changeset and check it is valid
      changeset = Changeset.find(id)
      raise OSM::APIChangesetNotYetClosedError, changeset if changeset.open?

      # Add a comment to the changeset
      comment = changeset.comments.create(:changeset => changeset,
                                          :body => body,
                                          :author => current_user)

      # Notify current subscribers of the new comment
      changeset.subscribers.visible.each do |user|
        UserMailer.changeset_comment_notification(comment, user).deliver_later if current_user != user
      end

      # Add the commenter to the subscribers if necessary
      changeset.subscribers << current_user unless changeset.subscribers.exists?(current_user.id)

      # Return a copy of the updated changeset
      @changeset = changeset
      render "api/changesets/show"

      respond_to do |format|
        format.xml
        format.json
      end
    end

    ##
    # Sets visible flag on comment to false
    def destroy
      # Check the arguments are sane
      raise OSM::APIBadUserInput, "No id was given" unless params[:id]

      # Extract the arguments
      id = params[:id].to_i

      # Find the changeset
      comment = ChangesetComment.find(id)

      # Hide the comment
      comment.update(:visible => false)

      # Return a copy of the updated changeset
      @changeset = comment.changeset
      render "api/changesets/show"

      respond_to do |format|
        format.xml
        format.json
      end
    end

    ##
    # Sets visible flag on comment to true
    def restore
      # Check the arguments are sane
      raise OSM::APIBadUserInput, "No id was given" unless params[:id]

      # Extract the arguments
      id = params[:id].to_i

      # Find the changeset
      comment = ChangesetComment.find(id)

      # Unhide the comment
      comment.update(:visible => true)

      # Return a copy of the updated changeset
      @changeset = comment.changeset
      render "api/changesets/show"

      respond_to do |format|
        format.xml
        format.json
      end
    end

    private

    ##
    # Check if the current user has exceed the rate limit for comments
    def rate_limit_exceeded?
      recent_comments = current_user.changeset_comments.where(:created_at => Time.now.utc - 1.hour..).count

      recent_comments >= current_user.max_changeset_comments_per_hour
    end
  end
end
