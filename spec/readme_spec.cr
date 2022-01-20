require "./spec_helper"

describe "Future example" do
  it "showcases #map, #select and #recover" do
    f = Future.new {
      sleep 2 # a placeholder for some expensive computation or for a lengthy IO operation
      "Success!"
    }

    f.map { |v| v.downcase }
      .select { |v| v.size < 3 }
      .recover { |ex| ex.message || ex.class.to_s }
      .await.should eq "Future::EmptyError"
  end

  it "showcases #zip and #flat_map" do
    db = DB.new
    author_f : Future(User) = db.user_by_id(1)
    reviewer_f : Future(User) = db.user_by_id(2)

    content_f = author_f.zip(reviewer_f) { |auth, rev|
      rev.groups.any? { |g| auth.reviewer_groups.includes? g } 
    }.flat_map { |reviewer_is_allowed|
      if reviewer_is_allowed
        db.content_by_user(1)
      else
        raise Exception.new
      end
    }
    
    content_f.on_success { |content|
      reviewer_f.await!.email(content)
    }.on_error { |ex| log_error(ex) }

    content_f.await.should eq ({id: 1, content: ["some content"]})
  end
end

class DB
  @users = [
    User.new(1, [1, 3, 42] of Int32, [] of Int32),
    User.new(2, [] of Int32, [42])
  ]
  @content = [
    {id: 1, content: ["some content"]}
  ]
  
  def user_by_id(n)
    Future.new {
      @users.find { |u| u.id == n }.not_nil!
    }
  end
  
  def content_by_user(n)
    Future.new {
      @content.find { |c| c[:id] == n }.not_nil!
    }
  end
end

def log_error(ex)
  puts "error #{ex.class}: #{ex.message}"
end

record User, id : Int32, reviewer_groups : Array(Int32), groups : Array(Int32) do
  def email(content)
    # Send the user an email with the given `content`
  end
end
