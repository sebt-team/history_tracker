# HistoryTracker [![Build Status](https://travis-ci.org/yoolk/history_tracker.png?branch=master)](https://travis-ci.org/yoolk/history_tracker) [![Code Climate](https://codeclimate.com/repos/527f070ec7f3a35566083437/badges/1e1ed5492aa1f25b3e36/gpa.png)](https://codeclimate.com/repos/527f070ec7f3a35566083437/feed) [![Dependency Status](https://gemnasium.com/yoolk/history_tracker.png)](https://gemnasium.com/yoolk/history_tracker) [![Coverage Status](https://coveralls.io/repos/yoolk/history_tracker/badge.png?branch=master)](https://coveralls.io/r/yoolk/history_tracker?branch=master)

**HistoryTracker** is inspired by [mongoid-history](https://github.com/aq1018/mongoid-history) and [audited](https://github.com/collectiveidea/audited). **HistoryTracker** tracks historical changes for any active record models, including its associations, and stores in MongoDB. It achieves this by storing all history tracks in a single collection that you define. Association models are referenced by storing an association path, which is an array of `model_name` and `model_id` fields starting from the top most parent and down to the assoication that should track history.

## Installation

This gem depends on ActiveRecord 3.x/4.x and Mongoid 3.x/4x.

```ruby
gem 'history_tracker', github: 'yoolk/history_tracker'
```

## Usage

#### Tracker class name

By default, an active record model will have `history_tracker_class` pointed to eg. `ListingHistoryTracker`.

```ruby
# app/models/listing.rb
class Listing < ActiveRecord::Base
  track_history
end

>> Listing.history_tracker_class # => ListingHistoryTracker
```

However, you can specify the history class name with `:class_name` options. All histories related to this model are stored in this tracker class.

```ruby
# app/models/listing.rb
class Listing < ActiveRecord::Base
  track_history class_name: 'Listing::HistoryTracker'
end

# app/models/listing/history_tracker.rb
class Listing::HistoryTracker
  include HistoryTracker::Mongoid::Tracker
end

>> Listing.history_tracker_class # => Listing::HistoryTracker
```

#### #current_user method name

By default, this gem will invoke `current_user` method and save its attributes on each change. However, you can change it by sets the `current_user_method` and `current_user_fields` using a Rails initializer.

```ruby
# config/initializers/history_tracker.rb
HistoryTracker.current_user_method = :authenticated_user

# Assume that authenticated_user returns #<User id: 1, email: 'chamnap@yoolk.com'>
>> listing = Listing.first
>> listing.update_attributes!(name: 'New Name')

>> listing.history_tracks.last.modifier_id #=> 1
```

#### Simple Model

HistoryTracker is simple to use. Just call `track_history` to a model to track changes on every create, update, and destroy.

```ruby
# app/models/listing.rb
class Listing < ActiveRecord::Base

  track_history   class_name:     'ListingHistoryTracker'          # specify the tracker class name, default is the newly mongoid class with "HistoryTracker" suffix
                  only:           [:name],                         # track only the specified fields
                  except:         [],                              # track all fields except the specified fields
                  on:             [:create, :update, :destroy],    # by default, it tracks all events
                  changes_method: :changes,                        # alternate changes method
                  parent:         nil,                             # it's for nested relation
                  inverse_of:     nil
end
```

This gives you a `history_tracks` method which returns historical changes to your model.

```ruby
# Assume that current_user returns #<User id: 1, email: 'chamnap@yoolk.com'>
>> listing = Listing.create(name: 'Listing 1')
>> track = listing.history_tracks.last
>> track.action       #=> create
>> track.modifier_id  #=> 1
>> track.original     #=> {}
>> track.modified     #=> {"name": "Listing 1"}

>> listing.update_attributes(name: 'New Listing 1')
>> track = listing.history_tracks.last
>> track.action       #=> update
>> track.modifier     #=> 1
>> track.original     #=> {"id" => 1, "name" => "Listing 1", "created_at"=>2013-03-12 06:25:51 UTC, "updated_at"=>2013-03-12 06:44:37 UTC}
>> track.modified     #=> {"name" => "New Listing 1"}

>> listing.destroy
>> track = listing.history_tracks.last
>> track.action     #=> destroy
>> track.modifier   #=> 1
>> track.original   #=> {"id" => 1, "name" => "Listing 1", "created_at"=>2013-03-12 06:25:51 UTC, "updated_at"=>2013-03-12 06:44:37 UTC}
>> track.modified   #=> {}
```

#### Examples

```ruby
# app/models/location.rb
class Location < ActiveRecord::Base
end

# app/models/listing.rb
class Listing < ActiveRecord::Base
  belongs_to :location
  has_many   :comments, dependent: :destroy

  track_history
end

# app/models/comment.rb
class Comment < ActiveRecord::Base
  belongs_to :listing

  track_history  class_name: 'Listing::History'
end

>> phnom_penh = Location.create(name: 'Phnom Penh')
>> siem_reap  = Location.create(name: 'Siem Reap')
>> listing = Listing.create(name: 'Listing 1', location: phnom_penh)
>> comment = listing.comments.create(body: 'Good listing')

>> comment.history_tracks.count #=> 1
>> listing.history_tracks.count #=> 2, including :comments

>> listing.update_attributes(location: siem_reap)
>> track = listing.history_tracks.last
>> track.original  # {"id" => 1, "name" => "Listing 1", "created_at"=>2013-03-12 06:25:51 UTC, "updated_at"=>2013-03-12 06:44:37 UTC, "location"=>{"id"=>1, "name"=>"Phnom Penh"}}
>> track.modified  # {"location"=>{"id"=>2, "name"=>"Siem Reap"}}
```

## Enable/Disable Tracking

Sometimes you don't want to store changes. Perhaps you are only interested in changes made by your users and don't need to store changes you make yourself in, say, a migration -- or when testing your application.

You can enable or disable tracking in three ways: globally, per class, or per method call.

#### Globally

On a global level you can disable tracking like this:

```ruby
>> HistoryTracker.enabled = false
```

For example, you might want to disable tracking in your Rails application's test environment to speed up your tests. This will do it:

```ruby
# in config/environments/test.rb
config.after_initialize do
  HistoryTracker.enabled = false
end
```

If you want to disable tracking inside `rails console` or `rake` script, add this:

```ruby
if defined?(Rails::Console) or File.basename($0) == "rake"
  HistoryTracker.enabled = false
end
```

#### Per class

If you are about change some widgets and you don't want to track your changes, you can disable/enable tracking like this:

```ruby
>> Listing.disable_tracking
>> Listing.enable_tracking
```

#### Per method call

You can call a method without tracking changes using `without_tracking`. It takes either a method name as a symbol:

```ruby
@listing.without_tracking(:destroy)
```

Or a block:

```ruby
@listing.without_tracking do
  @listing.update_attributes :name => 'New Listing 1'
end
```

#### Rails Controller

If your `ApplicationController` has a `current_user` method, HistoryTracker will invoke this method and store in the `modifier` field. Note that this column is a hash.

You may want HistoryTracker to call a different method to find out who is responsible. To do so, override the `user_for_history_tracker` method in your controller like this:

```ruby
class ApplicationController
  def user_for_history_tracker
    logged_in? ? current_member : {}  # or whatever
  end
end
```

You may want to disable HistoryTracker in some controllers. To do that, override the `set_history_tracker_enabled_for_controller` method in your controller like this:

```ruby
class ListingController
  def set_history_tracker_enabled_for_controller
    false
  end
end
```

It's possible to track custom operation with `write_history_track!`. It's good for complex relation or custom attributes.

```ruby
class ListingController
  def upload_logo
    logo_url = @listing.logo_url
    if @listing.upload_logo(params)
      @portal.write_history_track!(:update, logo_url: [logo_url, @listing.logo_url])
    end
  end
end
```

## Authors

* [Chamnap Chhorn](https://github.com/chamnap)