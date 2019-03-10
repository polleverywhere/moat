# TODOs

## ShortCircuitHelper

Investigate extracting the short-circuit code out of Poll Everywhere's `ApplicationPolicy` into mixins that can simply be included. The `ApplicationPolicy` in the README can look like this:

```rb
class ApplicationPolicy
  class Filter
    include Moat::ShortCircuitHelper::Filter

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    private

    attr_reader :user, :scope
  end

  class Authorization
    include Moat::ShortCircuitHelper::Authorization

    def initialize(user, resource)
      @user = user
      @resource = resource
    end

    private

    attr_reader :user, :resource
  end
end
```
