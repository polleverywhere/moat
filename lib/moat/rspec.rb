module Moat
  module RSpec
    module PolicyMatchers
      extend ::RSpec::Matchers::DSL

      matcher :permit_all_authorizations do
        match do |policy_class|
          @incorrectly_denied = policy_authorizations - permitted_authorizations(policy_class)
          @incorrectly_denied.empty?
        end
        failure_message do
          generate_failure_message(incorrectly_denied: @incorrectly_denied)
        end

        match_when_negated do
          false
        end
        failure_message_when_negated do
          "Cannot negate `permit_all_authorizations`: Use `only_permit_authorizations` instead"
        end
      end

      matcher :deny_all_authorizations do
        match do |policy_class|
          @incorrectly_permitted = permitted_authorizations(policy_class)
          @incorrectly_permitted.empty?
        end
        failure_message do
          generate_failure_message(incorrectly_permitted: @incorrectly_permitted)
        end

        match_when_negated do
          false
        end
        failure_message_when_negated do
          "Cannot negate `deny_all_authorizations`: Use `only_permit_authorizations` instead"
        end
      end

      matcher :only_permit_authorizations do |*authorizations_to_permit|
        match do |policy_class|
          permitted_authorizations = permitted_authorizations(policy_class)
          @incorrectly_permitted = permitted_authorizations - authorizations_to_permit
          @incorrectly_denied = authorizations_to_permit - permitted_authorizations
          @incorrectly_permitted.empty? && @incorrectly_denied.empty?
        end
        failure_message do
          generate_failure_message(
            incorrectly_permitted: @incorrectly_permitted,
            incorrectly_denied: @incorrectly_denied
          )
        end

        match_when_negated do
          false
        end
        failure_message_when_negated do
          "Cannot negate `only_permit_authorizations`: Specify all permitted authorizations instead"
        end
      end

      matcher :permit_through_all_filters do
        match do |policy_class|
          @incorrectly_denied = policy_filters - permitted_through_filters(policy_class)
          @incorrectly_denied.empty?
        end
        failure_message do
          generate_failure_message(incorrectly_denied: @incorrectly_denied)
        end

        match_when_negated do
          false
        end
        failure_message_when_negated do
          "Cannot negate `permit_through_all_filters`: Use `only_permit_through_filters` instead"
        end
      end

      matcher :deny_through_all_filters do
        match do |policy_class|
          @incorrectly_permitted = permitted_through_filters(policy_class)
          @incorrectly_permitted.empty?
        end
        failure_message do
          generate_failure_message(incorrectly_permitted: @incorrectly_permitted)
        end

        match_when_negated do
          false
        end
        failure_message_when_negated do
          "Cannot negate `deny_through_all_filters`: Use `only_permit_through_filters` instead"
        end
      end

      matcher :only_permit_through_filters do |*filter_whitelist|
        match do |policy_class|
          permitted_through_filters = permitted_through_filters(policy_class)
          @incorrectly_permitted = permitted_through_filters - filter_whitelist
          @incorrectly_denied = filter_whitelist - permitted_through_filters
          @incorrectly_permitted.empty? && @incorrectly_denied.empty?
        end
        failure_message do
          generate_failure_message(
            incorrectly_denied: @incorrectly_denied,
            incorrectly_permitted: @incorrectly_permitted
          )
        end

        match_when_negated do
          false
        end
        failure_message_when_negated do
          "Cannot negate `only_permit_through_filters`: Specify permitted filters instead"
        end
      end

      def generate_failure_message(incorrectly_permitted: [], incorrectly_denied: [])
        failure_descriptions = []
        unless incorrectly_permitted.empty?
          failure_descriptions << "Incorrectly permitted to #{role}: #{incorrectly_permitted.to_sentence}"
        end
        unless incorrectly_denied.empty?
          failure_descriptions << "Incorrectly denied to #{role}: #{incorrectly_denied.to_sentence}"
        end
        failure_descriptions.join("\n")
      end

      def role
        ::RSpec.current_example.metadata.fetch(:role)
      end

      def current_role
        public_send(role)
      end

      def permitted_authorizations(policy_class)
        policy_instance = policy_class::Authorization.new(current_role, policy_example_resource)
        policy_authorizations.select do |authorization|
          policy_instance.public_send(authorization)
        end
      end

      def permitted_through_filters(policy_class)
        policy_instance = policy_class::Filter.new(current_role, policy_example_scope)
        policy_filters.select do |filter|
          policy_instance.public_send(filter).include?(policy_example_resource)
        end
      end
    end

    module PolicyExampleGroup
      include Moat::RSpec::PolicyMatchers

      def self.included(base_class)
        base_class.metadata[:type] = :policy

        class << base_class
          def roles(*roles, &block)
            roles.each do |role|
              describe(role.to_s, role: role, caller: caller) { instance_eval(&block) }
            end
          end
          alias_method :role, :roles

          def resource(&block)
            fail ArgumentError, "#{__method__} called without a block" unless block
            let(:policy_example_resource) { instance_eval(&block) }
          end

          def scope(&block)
            fail ArgumentError, "#{__method__} called without a block" unless block
            let(:policy_example_scope) { instance_eval(&block) }
          end

          def policy_filters(*filters)
            let(:policy_filters) { filters }
          end

          def policy_authorizations(*authorizations)
            let(:policy_authorizations) { authorizations }
          end
        end

        base_class.class_eval do
          subject { described_class }

          let(:policy_authorizations) do
            fail NotImplementedError, "List of policy_authorizations undefined"
          end

          let(:policy_filters) do
            fail NotImplementedError, "List of policy_filters undefined"
          end

          let(:policy_example_resource) do
            fail NotImplementedError, "A resource has not been defined"
          end

          # a scope that contains at least the resource
          let(:policy_example_scope) do
            if policy_example_resource.class.respond_to?(:all)
              policy_example_resource.class.all
            else
              [policy_example_resource]
            end
          end
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include(
    Moat::RSpec::PolicyExampleGroup,
    type: :policy,
    file_path: %r{spec/policies}
  )
end
