# Moat

Moat is a minimalist authorization library for Ruby web applications, inspired by [Pundit](https://github.com/varvet/pundit). It is used today in production by Poll Everywhere and has been praised for its auditability and testability by security audit firms.

Moat features:

* Scope-first approach to resource authorization
* Fail-safe runtime assertions in the controller throw an exception if a Moat does *not* authorize a resource during a request
* RSpec matchers that make testing easy and fun for engineers, auditable by security auditing firms, and readable by non-technical people
* Plain' ol' Ruby objects (PORO) for better extensibility and to be more understandable to Ruby developers who have to dig into the guts of Moat

## Moat vs. Pundit

First, Pundit is awesome. We wrote this comparison to help us better understand if we should use Pundit or build this library. We found the differences compelling enough to build Moat, and maybe you too.

### What's the difference?

They are similar libraries, with an important distinction: Pundit is centered around authorizing individual resources, while Moat encourages filtering collections instead. The reasons for this are described below.

### Performance

If you are working with a collection (index actions, bulk actions, nested attributes, etc.), authorizing one object at a time can easily lead to N+1 performance problems. [Pundit](https://github.com/varvet/pundit) does have scopes, but only one per policy. This is not sufficient for authorizing multiple types of actions that involve collections.

### Security

Using scopes allows authorization to be applied before the sensitive data is loaded from the database. This is consistent with the Brakeman recommendation to not use an [Unscoped Find](https://brakemanscanner.org/docs/warning_types/unscoped_find/), also known as [Direct Object Reference](https://www.owasp.org/index.php/Top_10_2013-A4-Insecure_Direct_Object_References).

```rb
# Security risk: variable is populated with unauthorized data
@thing = Thing.find_by!(id: params[:id])
authorize(@thing)

# More secure: data is never loaded from the database
@thing = policy_filter(Thing).find_by!(id: params[:id])
```

## Installation

```rb
gem "moat"
```

Include Moat in your application controller:

```rb
class ApplicationController < ActionController::Base
  include Moat
  after_action :verify_policy_applied
end
```

## Policy Classes

Moat borrows from [Pundit](https://github.com/varvet/pundit) the concept that all authorization is done through _policy classes_: plain-ole-ruby-objects (POROs) that follow certain conventions:

- The name of the policy class is typically the name of a model class with the suffix "Policy". For example, `FooPolicy` contains the authorization rules for `Foo` models.
- Within its namespace, a policy can contain `Filter` and `Authorization` classes to filter collections and invidual resources, respectively.
- Public methods for `Authorization` classes should end in `?`.
- Public methods for `Filter` classes typically match the name of the Rails controller action.

### Example

```rb
class ArticlePolicy < ApplicationPolicy
  class Filter < Filter
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def update
      if !user
        scope.none
      elsif user.admin?
        scope.all
      else
        scope.where(user_id: user.id)
      end
    end

    private

    attr_reader :user, :scope
  end

  class Authorization < Authorization
    def initialize(user, resource)
      @user = user
      @resource = resource
    end

    def create?
      user
    end

    private

    attr_reader :user, :resource
  end
end

class ApplicationController < ActionController::Base
  include Moat
  after_action :verify_policy_applied
end

class ArticlesController < ApplicationController
  before_action :load_article, only: [:update]

  def create
    authorize(Article)
    @article = current_user.articles.create!(article_params)
  end

  def update
    @article.update!(article_params)
  end

  private

  def load_article
    @article = policy_filter(Article).find_by!(id: params[:id])
  end

  def article_params
    params.require(:article).permit(:title, :body)
  end
end
```

## API

`policy_filter(scope, action = action_name, user: moat_user, policy: <optional>)`

- Called from controller actions or `before_action`s
- Returns a `scope` with limitations according to `policy`
- Automagically tries to determine `policy` and `action` if not given

`authorize(resource, action = action_name, user: moat_user, policy: <optional>)`
- Called in controller methods
- Raises `Moat::NotAuthorizedError` if `user` is not permitted to take `action` on the resource according to `policy`
- Automagically tries to determine `policy` and `action` if not given

`authorized?(resource, action = action_name, user: moat_user, policy: <optional>)`
- Called in controller methods
- Returns `true` if `user` is permitted to take `action` on the resource according to `policy`, otherwise it returns `false`
- Automagically tries to determine `policy` and `action` if not given

`moat_user`
- Returns `current_user` unless overridden

`verify_policy_applied`
- For use as `after_action`
- Raises `Moat::PolicyNotAppliedError` unless `authorize` or `policy_filter` has been called
- Using this is highly recommended as a fail safe. However, it is not a replacement for good tests. Sometimes a controller action will need to authorize multiple scopes or resources. This verifies that a policy was applied at least once. It does not verify that a policy was applied to every resource referenced in your controller action.

`skip_verify_policy_applied`
- Called from controller actions
- Prevents `verify_policy_applied` from raising
- This removes an important fail-safe
- Never use this without making it super clear to future developers why it is safe to call this method

## Conventions

A Moat `policy` is a PORO that is initialized with a user and a scope
- Moat policies live in `app/policies` and are named after a resource suffixed with `Policy`
- Example: `AccountPolicy` represents the authorization logic for an `Account` and lives in `app/policies/account_policy.rb`

A `scope` is an Enumerable object representing a set of resources
- In a Rails app, this is almost always an `ActiveRecord::Relation`
- If you are not using an `ActiveRecord::Relation` you should document your policy very clearly. Properly using the interface between your policies and your controllers is essential for maintaining security.

Action methods for `Filter` classes should not end with `?`. If the user is not authorized for anything, then an empty collection/scope should be returned. Otherwise they should return a scope limited to the records the user has access to for the corresponding action.
Example:  `AccountPolicy#update` should return the scope of all accounts the user has permission to update.

Action methods for `Authorization` classes should end with `?`. If the return value is `true` (truthy) then the user is authorized to take the specified action on the resource.
Moat policy methods that do not end in `?`

Example: `AccountPolicy#update?` should return `true` only if a user is an administrator in the account.

## Rspec matchers

```rb
require "moat/rspec"

describe ThingPolicy do
  resource { Thing.create(owner: resource_owner) }
  policy_filters :index, :show, :edit, :update
  policy_authorizations :create?, :view_metadata?

  let(:superuser) { User.create(superuser: true) }
  let(:anonymous_user) { nil }
  let(:resource_owner) { User.create }
  let(:account_sibling) { User.create(account_id: resource_owner.account_id) }
  let(:non_account_sibling) { User.create }

  roles :superuser, :resource_owner do
    it { is_expected.to permit_through_all_filters }
    it { is_expected.to permit_all_authorizations }
  end

  role :account_sibling do
    it { is_expected.to only_permit_through_filters(:index, :show) }
    it { is_expected.to only_permit_authorizations(:create?) }
  end

  role :non_account_sibling do
    it { is_expected.to deny_through_all_filters }
    it { is_expected.to only_permit_authorizations(:create?) }
  end

  role :anonymous_user do
    it { is_expected.to deny_through_all_filters }
    it { is_expected.to deny_all_authorizations }
  end
end
```

If a non-standard scope is required for filters, it can be overridden. It defaults to the `all` relation for ActiveRecord models or a simple Array otherwise.

```ruby
scope { resource.container }
```

The current role can be referenced with `current_role`, or `role` for just the role name as a symbol.

When using `context` or `description` in combination with `roles`, we recommend that `roles` be the outermost nesting level. We've found that most of the time it's easier to maintain in the long term.

## Ensure all policies have full test coverage

```ruby
# spec/support/policy.rb
module PolicyRSpecHelpers
  def self.included(base_class)
    base_class.class_eval do
      # also a convenient place to define roles to be shared across policy specs
      let(:superuser) { User.create(superuser: true) }
      let(:anonymous_user) { nil }

      describe "spec/support/policy helper tests" do
        it "tests all defined filters" do
          public_methods = described_class::Filter.instance_methods(false)
          filters = begin
            policy_filters
          rescue NotImplementedError
            []
          end

          expect(filters).to match_array(public_methods)
        end

        it "tests all defined authorizations" do
          public_methods = described_class::Authorization.instance_methods(false)
          authorizations = begin
            policy_authorizations
          rescue NotImplementedError
            []
          end

          expect(authorizations).to match_array(public_methods)
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include(
    PolicyRSpecHelpers,
    type: :policy,
    file_path: %r{spec/policies}
  )
end
```

## Best Practices

1. The controller should handle filters motivated by the user's preferences, UI concerns; and performance concerns.

1. The Policy should only handle filters required by authorization rules.

1. It is OK if the controller and the Policy duplicate a `where` or `includes`. ActiveRecord and most database engines are good de-duplicate this.

1. The Policy `Filter` methods should add all `includes` and `where` clauses it needs itself. It should not make assumptions about how the argument is already scoped.

1. Be careful about your database indices. The actual SQL that is executed will depend on both the controller and policy code. For example, the following code would require a compound index on both subject_id and user_id.

   ```ruby
   # Controller
   def index
     @articles = policy_filter(Article.where(subject_id: params[:subject_id]))
   end

   # Policy
   def index
     scope.where(user_id: user.id)
   end
   ```

1. Use scopes (filters) when possible. But don't be afraid of authorizations when they make the code simpler.

1. Avoid making database queries in action methods in an `Authorize` class. The caller should eager load everything the policies needs to evaluate permissions. This helps to avoid N+1 performance problems if you need to check the permissions of multiple records.

1. Be careful with before_action/after_action/around_action. Rails makes it easy to share these with multiple controller actions. By default Moat implies the policy method from the controller action. When you use Moat via `authorize` or `policy_filter` be sure to test the behavior with every controller action that uses that before_action method.

   Mistake 1: Failing to define a policy action that is implicitly used.

   ```ruby
   class ThingsController < ApplicationController
     before_action :load_thing

     def show
     end

     def update
       @thing.update!(params.permit(:name))
     end

     private

     def load_things
       @thing = policy_filter(Thing).find(params[:id])
     end
   end

   class ThingPolicy < ApplicationPolicy
     class Filter < Filter
     def show
       scope.where(account_id: user.account_id)
     end

      # Oops. Forgot to add an `update` policy method.
     end
   end
   ```

   Mistake 2: Sharing the permission in a shared before_action, thus allowing access that should be denied.

   ```ruby
   class ThingsController < ApplicationController
     before_action :load_thing

     def show
     end

     def update
       @thing.update!(params.permit(:name))
     end

     private

     def load_things
       # Oops! `show` permissions are being used for `update` action
       @thing = policy_filter(Thing, :show).find(params[:id])
     end
   end

   class ThingPolicy < ApplicationPolicy
     class Filter < Filter
       def show
         scope.where(account_id: user.account_id)
       end

       def update
         scope.where(user_id: user.id)
       end
     end
   end
   ```


1. Use well-factored, clear names.

   ```ruby
   # OK because it is a simple case
   class ThingPolicy
     class Filter
       def show
         scope.where(user_id: user.id)
       end

       def update
         scope.where(account_id: user.account_id)
       end
     end
   end

   # Better because the filtering logic is labeled.
   class ThingPolicy
     class Filter
       def show
         accounts_things
       end
       def update
         (admin? && account_things) || users_things
       end

       private

       def users_things
         scope.where(user_id: user.id)
       end

       def accounts_things
         scope.where(account_id: user.account_id)
       end
     end
   end
   ```

1. Do authorization in controllers. If you are using background jobs, service objects, or presenters, authorize all the user input in the controller before passing responsibility to these other classes. This gives you a consistent place to verify whether or not you have implemented proper authorization.
