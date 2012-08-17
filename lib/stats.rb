require "lib/meta_repo.rb"

# TODO(dmac): Some of these calls could get really expensive as the size
# of our repos grow. We might need to eventually persist some of these stats
# in our db.
#
# TODO(dmac): These currently aggregate stats across all repos.
# We should expose /stats/:repo_name drill-down.

module Stats

  def self.get_commits(since, params)
    repos = params[:repo].nil? ? MetaRepo.instance.repos : MetaRepo.instance.repos_which_match(params[:repo])
    @commits = []
    repos.each do |repo|
      command_options = {:extended_regexp=>true, :regexp_ignore_case=>true}
      command_options[:cli_args] = ["origin/master", "--"]
      command_options[:author] = params[:author].split(",").join("|") if params[:author]
      command_options[:cli_args] = ["origin/#{params[:branch]}", "--"] if params[:branch]
      command_options[:after] = since
      @commits |= GitHelper.rev_list(repo, command_options)
    end

    # calculate reviewed, unreviewed, and commented commit counts
    reviewed_count = 0
    unreviewed_count = 0
    commented_count = 0
    commenter_counts = Hash.new { |h,k| h[k] = 0 }
    chatty_counts = Hash.new { |h,k| h[k] = 0 }
    @commits.each do |commit|
      commit_data = Commit.first("sha = ?", commit.id)
      commit_comment_data = Comment.filter("commit_id = ?", commit_data.id).all
      commit_comment_data.each do |comment|
        commenter_counts[User.first("id = ?", comment.user_id)] += 1
        chatty_counts[commit] += 1
      end
      if commit_data.approved_by_user.nil?
        commit_comment_data.empty? ? unreviewed_count += 1 : commented_count += 1
      else
        reviewed_count += 1
      end
    end
    commenter_counts_array = commenter_counts.sort { |user, count| user[1] <=> count[1] }.reverse[0..9]
    chatty_counts_array = chatty_counts.sort { |commit, count| commit[1] <=> count[1] }.reverse[0..9]
    {:reviewed_count => reviewed_count, :unreviewed_count => unreviewed_count,
        :commented_count => commented_count, :commit_count => @commits.size,
        :commenter_counts => commenter_counts_array, :chatty_counts => chatty_counts_array}
  end

  # def self.chatty_commits(since, params)
  #   dataset = Commit.
  #       join(:comments, :commit_id => :id).
  #       filter("`comments`.`created_at` > ?", since).
  #       join(:git_repos, :id => :commits__git_repo_id).
  #       group_and_count(:commits__sha, :git_repos__name___repo).order(:count.desc).limit(10)
  #   commits_sha_repo_count = dataset.all
  #   commits_and_counts = commits_sha_repo_count.map do |sha_repo_count|
  #     grit_commit = MetaRepo.instance.grit_commit(sha_repo_count[:repo], sha_repo_count[:sha])
  #     next unless grit_commit
  #     [grit_commit, sha_repo_count[:count]]
  #   end
  #   commits_and_counts.reject(&:nil?)
  # end
  #
  # def self.top_reviewers(since, params)
  #   user_ids_and_counts = User.join(:comments, :user_id => :id).
  #       filter("`comments`.`created_at` > ?", since).
  #       group_and_count(:users__id).order(:count.desc).limit(10).all
  #   users_and_counts = user_ids_and_counts.map do |id_and_count|
  #     [User[id_and_count[:id]], id_and_count[:count]]
  #   end
  # end
end
