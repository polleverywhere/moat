# require "spec_helper"
require_relative "../lib/moat"

# Will typically be a Rails controller
class MoatConsumerClass
  include Moat

  def current_user
    @current_user ||= Object.new
  end

  def action_name
    :read
  end
end

class IntegerPolicy
  class Filter
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def read
      if user == "specified user"
        scope
      else
        scope.select(&:even?)
      end
    end

    def show
      scope.select(&:odd?)
    end
  end

  class Authorization
    attr_reader :resource, :user

    def initialize(user, resource)
      @user = user
      @resource = resource
    end

    def read?
      resource.even? || user == "specified user"
    end

    def show?
      resource.odd?
    end
  end
end

class OtherIntegerPolicy
  class Filter
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def read
      scope.select(&:odd?)
    end

    def show
      scope.select(&:even?)
    end
  end

  class Authorization
    attr_reader :user, :resource

    def initialize(user, resource)
      @user = user
      @resource = resource
    end

    def read?
      resource.odd?
    end

    def show?
      resource.even?
    end
  end
end

describe Moat do
  let(:moat_consumer) { MoatConsumerClass.new }

  describe "#moat_user" do
    it "returns the value of #current_user" do
      expect(moat_consumer.moat_user).to eql(moat_consumer.current_user)
    end
  end

  describe "#policy_filter" do
    it "fails if scope is nil" do
      expect { moat_consumer.policy_filter(nil) }.
        to raise_error(Moat::PolicyNotFoundError)
    end

    it "fails if a corresponding policy can't be found" do
      expect { moat_consumer.policy_filter(Hash) }.
        to raise_error(Moat::PolicyNotFoundError, "Hash")
      expect { moat_consumer.policy_filter({}) }.
        to raise_error(Moat::PolicyNotFoundError, "Hash")
    end

    it "fails if a corresponding action can't be found" do
      expect { moat_consumer.policy_filter([1, 2, 3], :invalid_action, policy: IntegerPolicy) }.
        to raise_error(Moat::ActionNotFoundError, "IntegerPolicy::Filter#invalid_action")
    end

    it "returns the value of applying a policy scope filter to the original scope" do
      expect(moat_consumer.policy_filter([1, 2, 3, 4, 5], policy: IntegerPolicy)).to eql([2, 4])
    end

    it "uses specified action" do
      expect(moat_consumer.policy_filter([2, 3], :show, policy: IntegerPolicy)).to eql([3])
    end

    it "uses specified policy" do
      expect(moat_consumer.policy_filter([2, 3], policy: OtherIntegerPolicy)).
        to eql([3])
    end

    it "uses specified user" do
      expect(moat_consumer.policy_filter([2, 3], user: "specified user", policy: IntegerPolicy)).to eql([2, 3])
    end
  end

  describe "#authorize" do
    it "fails if resource is nil" do
      expect { moat_consumer.authorize(nil) }.
        to raise_error(Moat::PolicyNotFoundError)
    end

    it "fails if a corresponding policy can't be found" do
      expect { moat_consumer.authorize(Hash) }.
        to raise_error(Moat::PolicyNotFoundError, "Hash")
      expect { moat_consumer.authorize({}) }.
        to raise_error(Moat::PolicyNotFoundError, "Hash")
    end

    it "fails if a corresponding action can't be found" do
      expect { moat_consumer.authorize([1, 2, 3], :invalid_action?, policy: IntegerPolicy) }.
        to raise_error(Moat::ActionNotFoundError, "IntegerPolicy::Authorization#invalid_action?")
    end

    it "fails when the value of calling the policy method is false" do
      expect { moat_consumer.authorize(3) }.
        to raise_error(Moat::NotAuthorizedError, "unauthorized IntegerPolicy#read? for 3")
    end

    it "returns the initial resource value when the value of calling the policy method is true" do
      expect(moat_consumer.authorize(4)).to eql(4)
    end

    it "uses specified action" do
      expect(moat_consumer.authorize(3, :show?)).to eql(3)
    end

    it "uses specified policy" do
      expect(moat_consumer.authorize(3, policy: OtherIntegerPolicy)).to eql(3)
    end

    it "uses specified user" do
      expect(moat_consumer.authorize(3, user: "specified user")).to eql(3)
    end
  end

  describe "#verify_policy_applied" do
    context "authorize called" do
      it "does not raise an exception" do
        moat_consumer.authorize(4)
        expect { moat_consumer.verify_policy_applied }.not_to raise_error
      end
    end
    context "policy_filter called" do
      it "does not raise an exception" do
        moat_consumer.policy_filter([1, 2], policy: IntegerPolicy)
        expect { moat_consumer.verify_policy_applied }.not_to raise_error
      end
    end
    context "neither authorize nor policy_filter called" do
      it "raises an exception" do
        expect { moat_consumer.verify_policy_applied }.
          to raise_error(Moat::PolicyNotAppliedError)
      end
    end
  end

  describe "#skip_verify_policy_applied" do
    it "does not raise an exception when the policy was not applied" do
      moat_consumer.skip_verify_policy_applied
      expect { moat_consumer.verify_policy_applied }.not_to raise_error
    end
  end

  describe "policy lookup" do
    class FakePolicy
      class Filter
        attr_reader :scope

        def initialize(_user, scope)
          @scope = scope
        end

        def read
          scope.to_a
        end
      end
    end

    it "allows an object to specify a policy class" do
      class DefinesPolicyClass
        def self.to_a
          [1, 2]
        end

        def self.policy_class
          FakePolicy
        end
      end

      expect(moat_consumer.policy_filter(DefinesPolicyClass)).to eql([1, 2])
    end

    it "allows an object's class to specify a policy class" do
      class DefinesPolicyClass
        def self.policy_class
          FakePolicy
        end

        def to_a
          [3, 4]
        end
      end

      expect(moat_consumer.policy_filter(DefinesPolicyClass.new)).to eql([3, 4])
    end

    it "infers a policy if object is a class" do
      class Fake
        def self.to_a
          [5, 6]
        end
      end

      expect(moat_consumer.policy_filter(Fake)).to eql([5, 6])
    end

    it "infers a policy from an object's ancestor" do
      class Fake
        def self.to_a
          [7, 8]
        end
      end
      class FakeChild < Fake
      end

      expect(moat_consumer.policy_filter(FakeChild)).to eql([7, 8])
    end

    it "infers a policy from an object's class's ancestor" do
      class Fake
      end
      class FakeChild < Fake
        def to_a
          [9, 10]
        end
      end

      expect(moat_consumer.policy_filter(FakeChild.new)).to eql([9, 10])
    end

    it "infers a policy from an object's `model` method" do
      class DefinesModelName
        def self.model
          Fake
        end

        def self.to_a
          [11, 12]
        end
      end
      expect(moat_consumer.policy_filter(DefinesModelName)).to eql([11, 12])
    end
  end
end
