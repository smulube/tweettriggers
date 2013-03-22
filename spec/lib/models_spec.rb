require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

describe User do
  before(:each) do
    @user = User.create!(:twitter_name => 'TheRealRickAstley')
  end

  it "should have a twitter_name attribute" do
    @user.twitter_name.should == 'TheRealRickAstley'
  end

  it "should have a triggers association" do
    @user.triggers.create!
    @user.triggers.count.should == 1
    @user.triggers.should be_an_instance_of(Array)
    @user.triggers.each do |trigger|
      trigger.should be_an_instance_of(Trigger)
    end
  end
end

describe Trigger do
  before(:each) do
    @user = User.create!(:twitter_name => 'TheRealRickAstley')
    @trigger = @user.triggers.create!(
      :tweet => '{value}, {time}, {datastream}, {feed}, {feed_url}'
    )
    $redis = double("redis")
    $redis.stub!(:incr)
  end

  it "should belong to a user" do
    @trigger.user.should be_an_instance_of(User)
    @trigger.user.twitter_name.should == 'TheRealRickAstley'
  end

  it "should not find the trigger if searched for by another user" do
    user2 = User.create!(:twitter_name => 'FakeRick')
    trigger2 = user2.triggers.create!(
      :tweet => '{value}, {datastream}, {feed}, {feed_url}'
    )
    @user.triggers.find_by_trigger_hash(trigger2.trigger_hash).should be_nil
  end

  context "validation" do
    it "should generate the hash before validation" do
      @trigger.trigger_hash = nil
      @trigger.valid?
      @trigger.trigger_hash.should match(/\w+/)
    end

    it "should not overwrite existing hash" do
      hash = @trigger.trigger_hash
      @trigger.trigger_hash.should_not be_nil
      @trigger.valid?
      @trigger.trigger_hash.should == hash
    end
  end

  context "#send_tweet" do
    before(:each) do
      @now_time = Time.now
      @message = {
        'environment' => {
          'id' => 504
        },
        'triggering_datastream' => {
          'id' => 'myStreamId1',
          'value' => {
            'current_value' => '09120'
          }
        },
        'timestamp' => @now_time.iso8601(6)
      }.to_json

      Twitter.stub(:update)
    end

    it "should render the tweet and send it to Twitter" do
      Twitter.should_receive(:update).with("09120, myStreamId1, 504, https://cosm.com/feeds/504 at #{@now_time.strftime('%Y-%m-%d %T')}")
      @trigger.send_tweet(@message)
    end

    it "should truncate long messages so that the timestamp can always be appended" do
      @trigger.tweet = "This is a really long and rambling message that does not contain a date. This is a really long and rambling message that does not contain any urls just waffle"
      Twitter.should_receive(:update).with(@trigger.tweet[0, 140])
      @trigger.send_tweet(@message)
    end

    it "should handle tweets containing urls

    it "should increment our redis counter" do
      $redis.should_receive(:incr).with(TOTAL_JOBS)
      @trigger.send_tweet(@message)
    end

    it "should not send a tweet if the tweet text is nil" do
      Twitter.should_not_receive(:update)
      @trigger.tweet = nil
      @trigger.send_tweet('{}')
    end

    context "exceptions" do
      before(:each) do
        Twitter.stub(:update).and_raise(TriggerException)
      end

      it "should throw an exception if Twitter.update raises an error" do
        Twitter.should_receive(:update).with("09120, myStreamId1, 504, https://cosm.com/feeds/504 at #{@now_time.strftime('%Y-%m-%d %T')}").and_raise(TriggerException)
        expect {
          @trigger.send_tweet(@message)
        }.to raise_error(TriggerException)
      end

      it "should increment our error counter" do
        $redis.should_receive(:incr).with(TOTAL_ERRORS)
        expect {
          @trigger.send_tweet(@message)
        }.to raise_error(TriggerException)
      end

      it "should raise an exception if passed invalid JSON" do
        expect {
          @trigger.send_tweet("this is not json")
        }.to raise_error(TriggerException)
      end
    end
  end
end
