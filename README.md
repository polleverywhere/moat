# Moat

Moat is an small authorization library built for Ruby (primarily Rails) web applications.
Moat provides a small number of helpers and specific conventions for writing regular Ruby
classes to handle authorizations.


## Installation

TODO: Document this once this library is extracted into a gem.

## Policy Classes

Moat borrows from [Pundit](https://github.com/varvet/pundit) the concept that all authorization is done through instantiated policy classes. Policy classes are simply classes for plain-ole-ruby-objects (POROs) that follow a specific convention for their interface so that Moat's helper methods can easily apply the proper authorization. Those interface conventions are:


- The name of the policy is generally the name of a model class with the suffix "Policy". For example, `ArticlePolicy` is the class used to describe authorization for `Article` models. Moat's helper methods will automatically look up the policy according to this convention, but you can override this lookup by passing a `policy:` argument with the class to use.
- A policy will contain two classes within its namespace: `Filter` and `Authorization`.
- The initializer of both `Filter` and `Authorization` takes a user object as the 1st argument.
- The 2nd argument to `Filter` is a collection or scope. Usually this will be an ActiveRecord scope, but nothing in Moat requires this.
- The 2nd argument to `Authorization` is a resource that has already been loaded from the database. Often this will be an ActiveRecord object.
- The other public methods on both `Filter` and `Authorization` are called "action methods" and the helper methods use them to either apply a scope for a database query (`policy_filter`) or to check authorization for a loaded resource and return true if the user is authorized and false if they are not (`authorize`).
- Action methods that authorize a loaded resource should have a `?` as the suffix to their name while scope methods are just the name of the action. While you can specify the action method to use for either helper, the convention is to look it up by calling the `action_name` method. (For Rails controllers, that will be the name of the controller action.)

Below is a small example of a policy class that implements the interfaces for an update action -- both the scope and the resource methods. Note: while this is sometimes necessary, we recommend using just one of these action methods and preferring the scope-based methods wherever possible.

```ruby
class ArticlePolicy < ApplicationPolicy
  class Filter < Filter
    def update
      if user.account_admin?
        scope.where(account_id: user.account_id)
      else
        scope.where(user_id: user.id)
      end
    end
    alias_method :edit, :update
  end

  class Authorization < Authorization
    # Best practice would be to use a Filter for this.
    # This is here to show a more direct comparison to the Filter class.
    def update?
      if user.account_admin?
        resource.account_id == user.account_id
      else
        resource.user_id == user.id
      end
    end
    alias_method :edit?, :update?

    # This is a more realistic example of an action method
    # in an Authorization class. Since there are no existing
    # objects being acted on, we _can't_ use a database query
    # to scope this action to just records we are permitted to
    # act upon.
    def create?
      # Be careful your controller doesn't override resource.account_id
      # after this authorization check has been performed.
      user.account_admin? && resource.account_id == user.account_id
    end
  end
end

# An ApplicationPolicy class is not necessary, but it can help keep
# your policies DRY
class ApplicationPolicy
  class Filter
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    private

    attr_reader :user, :scope

    def account
      @account ||= user&.account
    end
  end

  class Authorization
    def initialize(user, resource)
      @user = user
      @resource = resource
    end

    private

    attr_reader :user, :resource

    def account
      @account ||= user&.account
    end
  end
end
```


Here are two example controllers — one that uses resource methods and one that uses scope methods. Generally `policy_filter` is preferred over `authorize`. Only use `authorize` when you cannot use a `Filter`  to prevent loading objects that the user may not be authorized to access.

```ruby
class ApplicationController < ActionController::Base
  include Moat
  include MoatVerification
end

class ArticleResourceController < ApplicationController
  before_action :load_article, only: [:edit, :update]
  before_action :load_new_article, only: [:new, :create]

  def edit
  end

  def update
    @article.update(article_params)
    redirect_to article_path(@article)
  end

  def create
    @article.save!
  end

  private

  def load_article
    # This is not recommended. It is shown for comparison
    # to the scope based approach.
    # See below about avoiding Direct Object References
    @article = Article.find(params[:id])
    authorize(article)
  end

  def load_new_article
    # This is a good example of using a authorize because there is
    # no collection to authorize against as it is a new record.
    @article = Article.new(account_id: current_user.account_id)
    authorize(@article)
  end
end

class ArticleScopeController < ApplicationController
  before_action :load_article, only: [:edit, :update]

  def index
    # policy_filter is always the better option for an index action.
    # The controller should handle filters motivated by:
    # - The user's preferences;
    # - UI concerns; and
    # - Performance concerns.
    # The Policy should only handle filters required by authorization rules.
    @articles = policy_filter(Article.search(params[:search])).limit(10)
  end

  def edit
  end

  def update
    @article.update(article_params)
    redirect_to article_path(@article)
  end

  private

  def load_article
    # This is the preferred method of loading a record from the database.
    @article = policy_filter(Article).find(params[:id])
  end
end
```

## API
- `policy_filter(scope, action = action_name, user: moat_user, policy: <optional>)`
  - Called from controller actions or `before_action`s
  - Returns a `scope` with limitations according to `policy`
  - Automagically looks up policy if not given
- `authorize(resource, action = action_name, user: moat_user, policy: <optional>)`
  - Called from controller actions or `before_action`s
  - Raises `Moat::NotAuthorizedError` if `user` is not permitted to take `action` according to `policy`
  - Automagically looks up policy if not given
- `moat_user`
  - Returns `current_user` unless overridden
- `verify_policy_applied`
  - For use as `after_action`
  - Raises `Moat::PolicyNotAppliedError` unless `authorize` or `policy_filter` has been called
  - Using this is highly recommended as a fail safe. However, it is not a replacement for good tests. Sometimes a controller action will need to authorize multiple scopes or resources. This verifies that a policy was applied at least once. It does not verify that a policy was applied to every resource referenced in your controller action.
- `skip_verify_policy_applied`
  - Called from controller actions
  - Prevents `verify_policy_applied` from raising
  - This removes an important fail-safe.
  - Never use this without making it super clear to future developers why it is safe to call this method.

## Conventions
- A Moat `policy` is a PORO that is initialized with a user and a scope
  - Moat policies live in `app/policies` and are named after a resource suffixed with `Policy`
  - Example: `AccountPolicy` represents the authorization logic for an `Account` and lives in `app/policies/account_policy.rb`
- A `scope` is an Enumerable object representing a set of resources
  - In a Rails app, this is almost always an `ActiveRecord::Relation`
  - If you are not using an `ActiveRecord::Relation` you should document your policy very clearly. Properly using the interface between your policies and your controllers is essential for maintaining security.
- Action methods for `Filter` classes should not end with `?`. If the user is not authorized for anything, then an empty collection/scope should be returned. Otherwise they should return a scope limited to the records the user has access to for the corresponding action.
  - Example:  `AccountPolicy#update` should return the scope of all accounts the user has permission to update.
- Action methods for `Authorization` classes should end with `?`. If the return value is `true` (truthy) then the user is authorized to take the specified action on the resource.
- Moat policy methods that do not end in `?`
  - Example: `AccountPolicy#update?` should return `true` only if a user is an administrator in the account.



## Pundit comparison

Moat borrows from [Pundit](https://github.com/varvet/pundit) the concept that all authorization is done through instantiated policy classes that are plain-ole-ruby-objects (POROs) that follow a specific convention for their interface.

Unlike [Pundit](https://github.com/varvet/pundit), Moat is focused on scope-based authorization yet easily allows for resource-based authorization within the same policy. This means we are primarily concerned with applying authorization by limiting your database queries to only return rows the specified user has access to.


### Why scope-based authorization?

#### Performance
If you are working with a collection (index actions, bulk actions, nested attributes, etc.), authorizing one object at a time can easily lead to N+1 performance problems.
[Pundit](https://github.com/varvet/pundit) does have support for scopes, but is only designed to have a single scope per policy, typically intended for `index` actions. However, listing objects is not the only action that involves a collection.

#### DRY
Using ActiveRecord scopes for authorization also works well.
Even if you are only loading one object, you can use the scope and just add `find` or `find_by` afterwards.

```ruby
def show
  @thing = policy_filter(Thing).find_by(id: params[:id])
end
```

#### Authorize early
Using scopes allows authorization to be applied before the sensitive data is even loaded out of the database.

This is consistent with the Brakeman recommendation to not use an [Unscoped Find](https://brakemanscanner.org/docs/warning_types/unscoped_find/), also known as [Direct Object Reference](https://www.owasp.org/index.php/Top_10_2013-A4-Insecure_Direct_Object_References).

```ruby
def show
  @thing = authorize(Thing.find(params[:id]))
end

def show
  @thing = policy_filter(Thing).find(params[:id])
end
```

#### 404 vs 403 vs. 401
Using scopes can make this a little bit more challenging, but only in a simplistic case.

There are really two questions:

- Are you authorized to know whether or not this resource exists? If not, 404 is the best response code.
- Are you authorized to perform this action?

```ruby
# Without scope.
# Returns 404 if the object does not exist.
# Returns 403 if the object exists and you are not authorized to destroy it.
# Implicitly allows everyone to know whether or not the object exists.
def destroy
  @thing = authorize(Thing.find(params[:id]))
  @thing.destroy!
end

# With scope
# Returns 404 if the resource doesn't exist OR if you aren't authorized to destroy it.
# Implies that if you don't have permission to destroy the object then you also
# don't have permission to know whether or not the object exists.
def destroy
  @thing = policy_filter(Thing).find(params[:id])
  @thing.destroy!
end

# Complex/combined scenario
# Returns 404 if you don't have permission to know whether or not the resource exists.
# Returns 403 if you can know it exists, but don't have permission to destroy.
def destroy
  @thing = authorize(policy_filter(Thing, :read).find_by(id: params[:id]))
  @thing.destroy!
end
```


## Rspec matchers

```ruby
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

If a non-standard scope is required for filters, it can be overridden. It
defaults to the `all` relation for ActiveRecord models or a simple Array
otherwise.

```ruby
scope { resource.container }
```

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

1. The controller should handle filters motivated by:

   - The user's preferences;
   - UI concerns; and
   - Performance concerns.

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
         (account_admin? && account_things) || users_things
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
