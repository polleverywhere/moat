module Moat
  POLICY_CLASS_SUFFIX = "Policy".freeze

  class Error < StandardError; end
  class PolicyNotAppliedError < Error; end
  class NotFoundError < Error; end
  class ActionNotFoundError < NotFoundError
    attr_reader :action, :resource, :policy, :user

    def initialize(options = {})
      return super if options.is_a?(String)
      @action = options[:action]
      @resource = options[:resource]
      @policy = options[:policy]
      @user = options[:user]

      message = options.fetch(:message) { "#{policy.name}##{action}" }
      super(message)
    end
  end

  class PolicyNotFoundError < NotFoundError; end
  class NotAuthorizedError < Error
    attr_reader :action, :resource, :policy, :user

    def initialize(options = {})
      return super if options.is_a?(String)
      @action = options[:action]
      @resource = options[:resource]
      @policy = options[:policy]
      @user = options[:user]

      message = options.fetch(:message) { "unauthorized #{policy.name}##{action} for #{resource}" }
      super(message)
    end
  end

  def policy_filter(scope, action = action_name, user: moat_user, policy: find_policy(scope))
    apply_policy(scope, action, user: user, policy: policy::Filter)
  end

  def authorized?(resource, action = "#{action_name}?", user: moat_user, policy: find_policy(resource))
    !!apply_policy(resource, action, user: user, policy: policy::Authorization)
  end

  def authorize(resource, action = "#{action_name}?", user: moat_user, policy: find_policy(resource))
    if authorized?(resource, action, user: user, policy: policy)
      resource
    else
      fail NotAuthorizedError, action: action, resource: resource, policy: policy, user: user
    end
  end

  def moat_user
    current_user
  end

  def verify_policy_applied
    fail PolicyNotAppliedError unless @_moat_policy_applied
  end

  def skip_verify_policy_applied
    @_moat_policy_applied = true
  end

  private

  alias policy_applied skip_verify_policy_applied

  def apply_policy(scope_or_resource, action, user:, policy:)
    policy_instance = policy.new(user, scope_or_resource)
    fail(ActionNotFoundError, action: action, policy: policy) unless policy_instance.respond_to?(action)

    policy_applied
    policy_instance.public_send(action)
  end

  def find_policy(object)
    policy = if object.nil?
      nil
    elsif object.respond_to?(:policy_class)
      object.policy_class
    elsif object.class.respond_to?(:policy_class)
      object.class.policy_class
    else
      infer_policy(object)
    end

    policy || fail(PolicyNotFoundError)
  end

  # Infer the policy from the object's type. If it is not found from the
  # object's class directly, go up the ancestor chain.
  def infer_policy(object)
    initial_policy_inference_class = policy_inference_class(object)
    policy_inference_class = initial_policy_inference_class
    while policy_inference_class
      policy = load_policy_from_class(policy_inference_class)
      return policy if policy
      policy_inference_class = policy_inference_class.superclass
    end

    fail PolicyNotFoundError, initial_policy_inference_class.name
  end

  def load_policy_from_class(klass)
    Object.const_get("#{policy_inference_class(klass).name}#{POLICY_CLASS_SUFFIX}")
  rescue NameError
    nil
  end

  def policy_inference_class(object)
    if object.respond_to?(:model) # For ActiveRecord::Relation
      object.model
    elsif object.is_a?(Class)
      object
    else
      object.class
    end
  end
end
