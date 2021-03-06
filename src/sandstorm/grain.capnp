# Sandstorm - Personal Cloud Sandbox
# Copyright (c) 2014 Sandstorm Development Group, Inc. and contributors
# All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

@0xc8d91463cfc4fb4a;

$import "/capnp/c++.capnp".namespace("sandstorm");

using Util = import "util.capnp";

# ========================================================================================
# Powerbox
#
# TODO(cleanup):  Put in separate file?
#
# The powerbox is part of the Sandstorm UI which allows users to connect applications to each
# other. There are two main modes in which a powerbox interaction can be driven: "request" and
# "offer".
#
# In "request" mode, an app initiates the powerbox by requesting to receive a capability matching
# some particular criteria using `SessionContext.request()` (or through the client-side
# postMessage() API, described in the documentation for `SessionContext.request()`). The user is
# presented with a list of other grains of theirs which might be able to fulfill this request and
# asked to choose one. Other grains initially register their ability to answer certain requests
# by filling in the powerbox fields of `UiView.ViewInfo`. When the user chooses a grain,
# `UiView.newRequestSession()` is called on the providing grain and the resulting UI session is
# displayed embedded in the powerbox. The providing grain can render a UI which prompts the user
# for additional details if needed, or implements some sort of additional picker. Once the grain
# knows which capability to provide, it calls `SessionContext.provide()` to fulfill the original
# request.
#
# In "offer" mode, an app initiates the powerbox by calling `SessionContext.offer()` in a normal,
# non-powerbox session, to indicate that it wishes to offer some capability to the current user
# for use in other apps. The user is presented with a list of apps and grains that are able to
# accept this offer. Grains can register interest in receiving offers by filling in the powerbox
# metadata in `UiView.ViewInfo`. Apps can also indicate in their manifest that it makes sense for a
# user to create a whole new grain to accept a powerbox offer. In either case, a session is created
# using `UiView.newOfferSession()`.

struct PowerboxDescriptor {
  # Describes properties of capabilities exported by the powerbox, or capabilities requested
  # through the powerbox.
  #
  # A PowerboxDescriptor specified individually describes the properties of a single object or
  # capability. It is a conjunction of "tags" describing different aspects of the object, such as
  # which interfaces it implements.
  #
  # Often, descriptors come in a list, i.e. List(PowerboxDescriptor). Such a list is usually a
  # disjunction describing one of two things:
  # - A powerbox "query" is a list of descriptors used in a request to indicate what kinds of
  #   objects the requesting app is looking for. (In a powerbox "offer" interaction, the "query"
  #   is the list of descriptors that the accepting app indicated it accepts in its `ViewInfo`.)
  # - A powerbox "provision" is a list of descriptors used to describe what kinds of objects an
  #   app provides, which can be requested by other apps. (In a powerbox "offer" interaction, the
  #   "provision" consists of the single descriptor that the offering app passed to `offer()`.)
  #
  # For a query to match a provision, at least one descriptor in the query must match at least one
  # descriptor in the provision (with an acceptable `matchQuality`; see below).
  #
  # Note that, in some use cases, where the "object" being granted is in fact just static data,
  # that data may be entirely encoded in tags, and the object itself may be a null capability.
  # For example, a powerbox request for a "contact" may result in a null capability with a tag
  # containing the contact details. Apps are free to define such conventions as they see fit; it
  # makes no difference to the system.

  tags @0 :List(Tag);
  # List of tags. For a query descriptor to match a provision descriptor, every tag in the query
  # must be matched by at least one tag in the provision. If the query tags list is empty, then
  # the query is asking for any capability at all; this occasionally makes sense in "meta" apps
  # that organize or communicate general capabilities.

  struct Tag {
    id @0 :UInt64;
    # A unique ID naming the tag. All such IDs should be created using `capnp id`.
    #
    # It is up to the developer who creates a new ID to decide what type the tag's `value` should
    # have (if any). This should be documented where the ID is defined, e.g.:
    #
    #     const preferredFrobberTag :UInt64 = 0xa170f46ec4b17829;
    #     # The value should be of type `Text` naming the object's preferred frobber.
    #
    # By convention, however, a tag ID is *usually* a Cap'n Proto type ID, with the following
    # meanings:
    #
    # * If `id` is the Cap'n Proto type ID of an interface, it indicates that the described
    #   powerbox capability will implement this interface. The interface's documentation may define
    #   what `value` should be in this case; otherwise, it should be null. (For example, a "file"
    #   interface might define that the `value` should be some sort of type descriptor, such as a
    #   MIME type. Most interfaces, however, will not define any `value`; the mere fact that the
    #   object implements the interface is the important part.)
    #
    # * If `id` is the type ID of a struct type, then `value` is an instance of that struct type.
    #   The struct type's documentation describes how the tag is to be interpreted.
    #
    # Note that these are merely conventions; nothing in the system actually expects tag IDs to
    # match Cap'n Proto type IDs, except possibly debugging tools.

    value @1 :AnyPointer;
    # An arbitrary value expressing additional metadata related to the tag.
    #
    # This is optional. "Boolean" tags (where all that matters is that they are present or
    # absent) -- including tags that merely indicate that an interface is implemented -- may leave
    # this field null.
    #
    # When "matching" two descriptors (one of which is a "query", and the other of which describes
    # a "provision"), the following algorithm is used to decide if they match:
    #
    # * A null pointer matches any value (essentially, null = wildcard).
    # * Pointers pointing to different object types (e.g. struct vs. list) do not match.
    # * Two struct pointers match if the primitive fields in both structs have identical values
    #   (bit for bit) and the corresponding pointer fields match by applying this algorithm
    #   recursively.
    # * Two lists of non-struct elements match if their contents match exactly.
    # * Lists of structs are treated as *sets*. They match if every element in the query list
    #   matches at least one element in the provider list. Order of elements is irrelevant.
    #
    # The above algorithm may appear quirky, but is designed to cover common use cases while being
    # relatively simple to implement. Consider, for example, a powerbox query seeking to match
    # "video files". All "files" are just byte blobs; file managers probably don't implement
    # different interfaces for different file types. So, you will want to use tags here. For
    # example, a MIME type tag might be defined as:
    #
    #     struct MimeType {
    #       category @0 :Text;
    #       subtype @1 :Text;
    #       tree @2 :Text;    // e.g. "vnd"
    #       suffix @3 :Text;  // e.g. "xml"
    #       params @4 :List(Param);
    #       struct Param {
    #         name @0 :Text;
    #         value @1 :Text;
    #       }
    #     }
    #
    # You might then express your query with a tag with `id` = MimeType's type ID and value =
    # `(category = "video")`, which effectively translates to a query for "video/*". (Your query
    # descriptor would have a second tag to indicate what Cap'n Proto interface the resulting
    # capability should implement.)
  }

  quality @1 :MatchQuality = acceptable;
  # Use to indicate a preference or anti-preference for this descriptor compared to others in the
  # same list.
  #
  # When a descriptor in the query matches multiple descriptors in the provision, or vice versa,
  # exactly one of the matches is chosen to decide the overall `matchQuality`, as follows:
  # - If one matching descriptor is strictly less-specific than some other in the match set, it is
  #   discarded. (A descriptor A is strictly less-specific than a descriptor B if every possible
  #   match for B would also match A.)
  # - Once all less-specific descriptors are eliminated, of those that remains, the descriptor with
  #   the best `matchQuality` is chosen.

  enum MatchQuality {
    # The values below are listed in order from "best" to "worst". Note that this ordering does NOT
    # correspond to the numeric order. Also note that new values could be introduced in the future.

    preferred @1;
    # Indicates that this match should be preferred over other options. The powerbox UI may
    # encourage the user to choose preferred options. For example, a document editor that uses
    # the powerbox to import document files might indicate that it accepts docx format but prefers
    # odf, perhaps because its importer for the latter is higher-quality. Similarly, it might
    # publish powerbox capabilities to export as either format, but again mark odf as preferred.
    #
    # Note `preferred` is only meaningful if the descriptor list contains other descriptors that
    # are marked `acceptable`. An app cannot promote itself over other apps by marking its
    # provisions as `preferred`. (A requesting app could indicate a preference for a particular
    # providing app, though, if the providing app provides a unique tag that the requestor can
    # mark as preferred.)

    acceptable @0;
    # Indicates that this is a fine match which should be offered to the user as a regular option.
    # This is the default.

    # TODO(someday): mightWork @3;
    # Indicates that the match might have useful results but there is a non-negligible priority
    # that it won't work, and this option should be offered to the user only as an advanced option.

    unacceptable @2;
    # "Unacceptable" matches are expected *not* to work and therefore will not be offered to the
    # user.
    #
    # Note that `unacceptable` can be used to filter out a subset of matches of a broader
    # descriptor by taking advantage of the fact that the powerbox prefers more-specific matches
    # over less-specific ones. For instance, you could query for "files except video files" by
    # specifying a query with two descriptors: a descriptor for "implements File" with quality
    # "acceptable" and a second descriptor for "implements File with type = video" with quality
    # "unacceptable".
  }
}

struct PowerboxDisplayInfo {
  # Information about a powerbox link (i.e., the result of a powerbox interaction) which could be
  # displayed to the user when auditing powerbox-granted capabilities.

  title @0 :Util.LocalizedText;
  # A short, human-readable noun phrase describing the object this capability represents. If null,
  # the grain's title will be used -- this is appropriate if the capability effectively represents
  # the whole grain.
  #
  # The title is used, for example, when the user is selecting multiple capabilities, building a
  # list.

  verbPhrase @1 :Util.LocalizedText;
  # Verb phrase describing what the holder of this capability can do to the grain, e.g.
  # "can edit".  This may be displayed in the sharing UI to describe a connection between two
  # grains.

  description @2 :Util.LocalizedText;
  # Long-form description of what the capability represents.  Should be roughly a paragraph that
  # could be displayed e.g. in a tooltip.
}

# ========================================================================================
# Runtime interface

interface SandstormApi(AppObjectId) {
  # The Sandstorm platform API, exposed as the default capability over the two-way RPC connection
  # formed with the application instance.  This object specifically represents the supervisor
  # for this application instance -- two different application instances (grains) never share a
  # supervisor.
  #
  # `AppObjectId` is the format in which the application identifies its persistent objects which
  # can be saved from the outside; see `AppPersistent`, below.

  # TODO(soon):  Read the grain title as set by the user.  Also have interface to offer a new
  #   title and icon?

  deprecatedPublish @0 ();
  deprecatedRegisterAction @1 ();
  # These powerbox-related methods were never implemented. Eventually it was decided that they
  # specified the wrong model.

  shareCap @2 (cap :Capability, displayInfo :PowerboxDisplayInfo)
           -> (sharedCap :Capability, link :SharingLink);
  # Share a capability, so that it may safely be sent to another user.  `sharedCap` is a wrapper
  # (membrane) around `cap` which can have a petname assigned and can be revoked via `link`.  The
  # share is automatically revoked if `link` is discarded.  If `cap` is persistable, then both
  # `sharedCap` and `link` also are.
  #
  # This method is intended to be used by programs that actually implement a communications link
  # over which a capability could be sent from one user to another.  For example, a chat app would
  # use this to prepare a capability to be embedded into a message.  In these cases, capabilities
  # may be shared without going through the system sharing UI, and therefore the application must
  # set up the sharing link itself.
  #
  # In general, you should NOT call this on a capability that you will then pass to
  # `SessionContext.offer()`.

  shareView @3 (view :UiView) -> (sharedView :UiView, link :ViewSharingLink);
  # Like `shareCap` but with extra options for sharing a UiView, such as setting a role and
  # permissions.

  save @8 (cap :Capability, label :Util.LocalizedText) -> (token :Data);
  # Saves a persistent capability and returns a token which can be used to restore it later
  # (including in a future run of the app) via `restore()` (below). Not all capabilities can be
  # saved -- check the documentation for the capability you are using to see if it is described as
  # "persistent".
  #
  # The grain owner will be able to inspect saved capabilities via the UI. `label` will be shown
  # there and should briefly describe what this capability is used for.
  #
  # To see how to make your own app's objects persistent, see the `AppPersistent` interface defined
  # later in this file. Note that it's perfectly valid to pass your app's own capabilities to
  # `save()`, if they are persistent in this way.
  #
  # (Under the hood, `SandstormApi.save()` calls the capability's `AppPersistent.save()` method,
  # then stores the result in a table indexed by the new randomly-generated token. The app CANNOT
  # call `AppPersistent.save()` on external capabilities itself; such calls will be blocked by the
  # supervisor (and the result would be useless to you anyway, because you have no way to restore
  # it). You must use `SandstormApi.save()` so that saved capabilities can be inspected by the
  # user.)

  restore @4 (token :Data, requiredPermissions :PermissionSet) -> (cap :Capability);
  # Given a token previously returned by `save()`, get the capability it pointed to. The returned
  # capability should implement the same interfaces as the one you saved originally, so you can
  # downcast it as appropriate.
  #
  # `requiredPermissions` specifies permissions which must be held on *this* grain by the user
  # who originally introduced this token. This way, if a user of a grain connects the grain to
  # other resources, but later has their access to the grain revoked, these connections are revoked
  # as well.
  #
  # Consider this example: Alice owns a grain which implements a discussion forum. At some point,
  # Alice invites Dave to participate in the forum, and she gives him moderator permissions. As
  # part of being a moderator, Dave arranges to have a notification emailed to him whenever a post
  # is flagged for moderation. To set this up, the forum app makes a powerbox request for an email
  # send capability directed to his email address. Later on, Alice decides to demote Dave from
  # "moderator" status to "participant". At this point, Dave should stop receiving email
  # notifications; the capability he introduced in the powerbox request should be revoked. Alice
  # actually has no idea that Dave set up to receive these notifications, so she does not know
  # to revoke it manually; we want it to happen automatically, or at least we want to be able to
  # call Alice's attention to it.
  #
  # To this end, when the Powerbox request is made through Dave and he chooses a capability, the
  # returned capability token is tagged as having come from Dave. When the app restore()s the token,
  # it indicates that whoever introduced the token must have the "moderator" permission. If Dave
  # has lost this permission, then the restore() will fail.

  drop @5 (token :Data);
  # Deletes the token and frees any resources being held with it. Once drop()ed, you can no longer
  # restore() the token. This call is idempotent: it is not an error to `drop()` a token that has
  # already been dropped.

  deleted @6 (ref :AppObjectId);
  # Notifies the supervisor that an object hosted by this application has been deleted, and
  # therefore all references to it may as well be dropped. This affects *incoming* references,
  # whereas `drop()` affects *outgoing*.

  stayAwake @7 (displayInfo :NotificationDisplayInfo, notification :OngoingNotification)
            -> (handle :Util.Handle);
  # Requests that the app be allowed to continue running in the background, even if no user has it
  # open in their browser. An ongoing notification is delivered to the user who owns the grain to
  # let them know of this. The user may cancel the notification, in which case the app will no
  # longer be kept awake. If not canceled, the app remains awake at least until it drops `handle`.
  #
  # Unlike other ongoing notifications, `notification` in this case need not be persistent (since
  # the whole point is to prevent the app from restarting), and `handle` is not persistent.
  #
  # WARNING: A machine failure or similar situation can still cause the app to shut down at any
  #   time. Currently, the app will NOT be restarted after such a failure.
  #
  # TODO(someday): We could make `handle` be persistent. If the app persists it -- and if
  #   `notification` is persistent -- we would automatically restart the app after an unexpected
  #   failure.
}

interface UiView {
  # Implements a user interface with which a user can interact with the grain.  We call this a
  # "view" because a single grain may actually have multiple "views" that provide different
  # functionality or represent multiple logical objects in the same physical grain.
  #
  # When an application starts up, it must export an instance of UiView as its starting
  # capability on the Cap'n Proto two-party connection.  This represents the grain's main view and
  # is what the user will see when they open the grain.
  #
  # It is possible for a grain to export additional views via the usual powerbox mechanisms.  For
  # instance, a spreadsheet app might let the user create a "view" of a few cells of the
  # spreadsheet, allowing them to share those cells to another user without sharing the entire
  # sheet.  To accomplish this, the app would create an alternate UiView object that implements
  # an interface just to those cells, and then would use `UiSession.offer()` to offer this object
  # to the user.  The user could then choose to open it, share it, save it for later, etc.

  getViewInfo @0 () -> ViewInfo;
  # Get metadata about the view, especially relating to sharing.

  struct ViewInfo {
    permissions @0 :List(PermissionDef);
    # List of permission bits which apply to this view.  Permissions typically include things like
    # "read" and "write".  When sharing a view, the sending user may select a set of permissions to
    # grant to the receiving user, and may modify this set later on.  When a new user interface
    # session is initiated, the platform indicates which permissions the user currently has.
    #
    # The grain's owner always has all permissions.
    #
    # It is important that new versions of the app only add new permissions, never remove existing
    # ones, since permission IDs are indexes into the list and persist through upgrades.
    #
    # In a true capability system, permissions would normally be implemented by wrapping the main
    # view in filters that prohibit disallowed actions.  For example, to give a user read-only
    # access to a grain, you might wrap its UiView in a wrapper that checks all incoming requests
    # and disallows the ones that would modify the content.  However, this approach does not work
    # terribly well for UiView for a few reasons:
    #
    # - For complex UIs, HTTP is often the wrong level of abstraction for this kind of filtering.
    #   It _may_ work for modern apps that push all UI logic into static client-side Javascript and
    #   only serve RPCs over dynamic HTTP, but it won't work well for many legacy apps, and we want
    #   to be able to port some of those apps to Sandstorm.
    #
    # - If a UiView is reshared several times, each time adding a new filtering wrapper, then
    #   requests could get slow as they have to pass through all the separate filters.  This would
    #   be especially bad if some of the filters live in other grains, as those grains would have
    #   to spin up whenever the resulting view is used.
    #
    # - Compared to computers, humans are relatively less likely to be vulnerable to confused
    #   deputy attacks and relatively more likely to be confused by the concept of having multiple
    #   capabilities to the same object that provide different access levels.  For example, say
    #   Alice and Bob both share the same document to Carol, but Alice only grants read access
    #   while Bob gives read/write.  Carol should only see one instance of the document in her
    #   grain list and she should see the read/write interface when she opens it.  But this instance
    #   isn't simply the one she got from Bob -- if Bob revokes his share but Alice continues to
    #   share read rights, Carol should now see the read-only interface when she opens the same
    #   grain.
    #
    # To solve all three problems, we have permission bits that are processed when creating a new
    # session.  Instead of filtering individual requests, wrappers of UiView only need to filter
    # calls to `newSession()` in order to restrict the permission set as appropriate.  Once a
    # session is thus created, it represents a direct link to the target grain.  Also, the platform
    # can implement special handling of sharing and permission bits that allow it to recognize when
    # two UiViews are really the same view with different permissions applied, and can then combine
    # them in the UI as appropriate.
    #
    # It is actually entirely possible to implement a traditional filtering membrane around a
    # UiView, perhaps to implement a kind of access that can't be expressed using the permission
    # bits defined by the app.  But doing so will be awkward, slow, and confusing for all the
    # reasons listed above.

    roles @1 :List(RoleDef);
    # Choosing individual permissions is not very intuitive for most users.  Therefore, the sharing
    # interface prefers to offer the user a list of "roles" to assign to each recipient.  For
    # example, a document might have roles like "editor" and "viewer".  Each role corresponds to
    # some list of permissions.  The application may define a set of roles to offer via this list.
    #
    # In addition to the roles in this list, the sharing interface will always offer a "full access"
    # or "same as me" option.  So, it only makes sense to define roles that represent less than
    # "full access", and leaving the role list entirely empty is reasonable if there are no such
    # restrictions to offer.
    #
    # It is important that new versions of the app only add new roles, never remove existing ones,
    # since role IDs are indexes into the list and persist through upgrades.

    deniedPermissions @2 :PermissionSet;
    # Set of permissions which will be removed from the permission set when creating a new session
    # though this object.  This set should be empty for the grain's main UiView, but when that view
    # is shared with less than full access, recipients will get a proxy UiView which has a non-empty
    # `deniedPermissions` set.
    #
    # It is not the caller's responsibility to enforce this set.  It is provided mainly so that the
    # sharing UI can avoid offering options to the user that don't make sense.  For instance, if
    # Alice has read-only access to a document and wishes to share the document to Bob, the sharing
    # UI should not offer Alice the ability to share write access, because she doesn't have it in
    # the first place.  The sharing UI figures out what Alice has by examining `deniedPermissions`.

    matchRequests @3 :List(PowerboxDescriptor);
    # Indicates what kinds of powerbox requests this grain may be able to fulfill. If the grain
    # is chosen by the user during a powerbox request, then `newRequestSession()` will be called
    # to set up the embedded UI session.

    matchOffers @4 :List(PowerboxDescriptor);
    # Indicates what kinds of powerbox offers this grain is interested in accepting. If the grain
    # is chones by the user during a powerbox offer, then `newOfferSession()` will be called
    # to start a session around this.
  }

  newSession @1 (userInfo :UserInfo, context :SessionContext,
                 sessionType :UInt64, sessionParams :AnyPointer)
             -> (session :UiSession);
  # Start a new user interface session.  This happens when a user first opens the view, or when
  # the user returns to a tab that has been inactive long enough that the server was killed off in
  # the meantime.
  #
  # `userInfo` specifies the user's display name and permissions, as authenticated by the system.
  #
  # `context` contains callbacks that can be used to invoke system functionality in the context of
  # the session, such as displaying the powerbox.
  #
  # `sessionType` is the type ID specifying the interface which the returned `session` should
  # implement.  All views should support the `WebSession` interface to support opening the view
  # in a browser.  Other session types might be useful for e.g. desktop and mobile apps.
  #
  # `sessionParams` is a struct whose type is specified by the session type.  By convention, this
  # struct should be defined nested in the session interface type with name "Params", e.g.
  # `WebSession.Params`.  This struct contains some arbitrary startup information.

  newRequestSession @2 (userInfo :UserInfo, context :SessionContext,
                        sessionType :UInt64, sessionParams :AnyPointer,
                        requestInfo :List(PowerboxDescriptor))
                    -> (session :UiSession);
  # Creates a new session based on a powerbox request. `requestInfo` is the subset of the original
  # request description which matched descriptors that this grain indicated it provides via
  # `ViewInfo.matchRequests`. The list is also sorted with the "best match" first, such that
  # it is reasonable for a grain to ignore all descriptors other than the first.
  #
  # Keep in mind that, as with any other session, the UiSession capability could become
  # disconnected randomly and the front-end will then reconnect by calling `newRequestSession()`
  # again with the same parameters. Generally, apps should avoid storing any session-related state
  # on the server side; it's easy to use client-side sessionStorage instead.

  newOfferSession @3 (userInfo :UserInfo, context :SessionContext,
                      sessionType :UInt64, sessionParams :AnyPointer,
                      offer :Capability, descriptor :PowerboxDescriptor)
                  -> (session :UiSession);
  # Creates a new session based on a powerbox offer. `offer` is the capability being offered and
  # `descriptor` describes it.
  #
  # By default, an "offer" session is displayed embedded in the powerbox much like a "request"
  # session is. If the the session implements a quick action -- say "share to friend by email" --
  # then it may make sense for it to remain embedded, returning the user to the offering app when
  # done. The app may call `SessionContext.close()` to indicate that it's time to close. However,
  # in some cases it makes a lot of sense for the app to become "full-frame", for example a
  # document editor app accepting a document offer may want to then open the editor for long-term
  # use. Such apps should call `SessionContext.openView()` to move on to a full-fledged session.
  # Finally, some apps will take an offer, wrap it in some filter, and then make a new offer of the
  # wrapped capability. To that end, calling `SessionContext.offer()` will end the offer session
  # but immediately start a new offer interaction in its place using the new capability.
  #
  # Keep in mind that, as with any other session, the UiSession capability could become
  # disconnected randomly and the front-end will then reconnect by calling `newOfferSession()`
  # again with the same parameters. Generally, apps should avoid storing any session-related state
  # on the server side; it's easy to use client-side sessionStorage instead. (Of course, if the
  # session calls `SessionContext.openView()`, the new view will be opened as a regular session,
  # not an offer session.)
}

# ========================================================================================
# User interface sessions

interface UiSession {
  # Base interface for UI sessions.  The most common subclass is `WebSession`.
}

struct UserInfo {
  # Information about the user opening a new session.
  #
  # TODO(soon):  More details:
  # - Profile:  Profile link?
  # - Sharing/authority chain:  "Carol (via Bob, via Alice)"
  # - Identity:  Public key, certificates, verification of proxy chain.

  displayName @0 :Util.LocalizedText;
  # Name by which to identify this user within the user interface.  For example, if two users are
  # editing a document simultaneously, the application may display each user's cursor position to
  # the other, labeled with the respective display names.  As the users edit the document, the
  # document's history may be annotated with the display name of the user who made each change.
  # Display names are NOT unique nor stable:  two users could potentially have the same display
  # name and a user's display name could change.

  preferredHandle @4 :Text;
  # The user's preferred "handle", as set in their account settings. This is guaranteed to be
  # composed only of lowercase English letters, digits, and underscores, and will not start with
  # a digit. It is NOT guaranteed to be unique; if your app dislikes duplicate handles, it must
  # check for them and do something about them.

  pictureUrl @6 :Text;
  # URL of the user's profile picture, appropriate for displaying in a 64x64 context.

  pronouns @5 :Pronouns;
  # Indicates which pronouns the user prefers you use to refer to them.

  enum Pronouns {
    neutral @0;  # "they"
    male @1;     # "he" / "him"
    female @2;   # "she" / "her"
    robot @3;    # "it"
  }

  deprecatedPermissionsBlob @1 :Data;
  permissions @3 :PermissionSet;
  # Set of permissions which this user has.  The exact set might not correspond directly to any
  # particular role for a number of reasons:
  # - The sharer may have toggled individual permissions through the advanced settings.
  # - If two different users share different roles to a third user, and neither of the roles is a
  #   strict superset of the other, the user gets the union of the two permissions.
  # - If Alice shares role A to Bob, and Bob further delegates role B to Carol, then Carol's
  #   permissions are the intersection of those granted by roles A and B.
  #
  # That said, some combinations of permissions may not make sense.  For example, a document editor
  # probably has no reasonable way to implement write permission without read permission.  It is up
  # to the application to decide what to do in this case, but simply ignoring the nonsensical
  # permissions is often a fine strategy.
  #
  # If the user's permissions are reduced while the session is opened, the session will be closed
  # by the platform and the user forced to start a new one.  If the user's permissions are increased
  # while the session is opened, the system will prompt them to start a new session to use the new
  # permissions.  Either way, the application need not worry about permissions changing during a
  # session.

  identityId @2 :Data;
  # A unique, stable identifier for the calling user. This is computed such that a user's ID will
  # be the same across all Sandstorm servers, and will not collide with any other identity ID in the
  # world. Therefore, grains transferred between servers can still count on the user IDs being the
  # same and secure (unless the new host is itself malicious, of course, in which case all bets are
  # off).
  #
  # The ID is actually a SHA-256 hash, therefore it is always exactly 32 bytes and the app can
  # safely truncate it down to some shorter prefix according to its own security/storage trade-off
  # needs.
  #
  # If the user is not logged in, `userId` is null.
}

interface SessionContext {
  # Interface that the application can use to call back to the platform in the context of a
  # particular session.  This can be used e.g. to ask the platform to present certain system
  # dialogs to the user.

  getSharedPermissions @0 () -> (var :Util.Assignable(PermissionSet).Getter);
  # Returns an observer on the permissions held by the user of this session.
  # This observer can be persisted beyond the end of the session.  This is useful for detecting if
  # the user later loses their access and auto-revoking things in that case.  See also `tieToUser()`
  # for an easier way to make a particular capability auto-revoke if the user's permissions change.

  tieToUser @1 (cap :Capability, requiredPermissions :PermissionSet,
                displayInfo :PowerboxDisplayInfo)
            -> (tiedCap :Capability);
  # Create a version of `cap` which will automatically stop working if the user no longer holds the
  # permissions indicated by `requiredPermissions` (and starts working again if the user regains
  # those permissions).  The capability also appears connected to the user in the sharing
  # visualization.
  #
  # Keep in mind that, security-wise, calling this also implies exposing `tiedCap` to the user, as
  # anyone with a UiView capability can always initiate a session and pass in their own
  # `SessionContext`.  If you need to auto-revoke a capability based on the user's permissions
  # _without_ actually passing that capability to the user, use `getSharedPermissions()` to detect
  # when the user's permissions change and implement it yourself.

  offer @2 (cap :Capability, requiredPermissions :PermissionSet,
            descriptor :PowerboxDescriptor, displayInfo :PowerboxDisplayInfo);
  # Offer a capability to the user.  A dialog box will ask the user what they want to do with it.
  # Depending on the type of capability (as indicated by `descriptor`), different options may be
  # provided.  All capabilities will offer the user the option to save the capability to their
  # capability/grain store.  Other type-specific actions may be offered by the platform or by other
  # applications.
  #
  # For example, offering a UiView will give the user options like "open in new tab", "save to
  # grain list", and "share with another user".
  #
  # The capability is implicitly tied to the user as if via `tieToUser()`.

  request @3 (query :List(PowerboxDescriptor)) -> (cap :Capability, descriptor :PowerboxDescriptor);
  # Although this method exists, it is unimplemented and currently you are meant to use the
  # postMessage api to get a token, and then restore that token with SandstormApi.restore().
  #
  # The postMessage api is an rpc interface so you will have to listen for a `message` callback
  # after sending a postMessage. The postMessage object should have the following form:
  #
  # powerboxRequest:
  #   rpcId: A unique string that should identify this rpc message to the app. You will receive this
  #          id in the callback to verify which message it is referring to.
  #   query: A list of PowerboxDescriptor objects, serialized as a Javascript array OR a
  #          base64-encoded powerbox query created using the `spk query` tool.
  #   saveLabel: A string petname to give this label. This will be displayed to the user as the name
  #          for this capability.
  #
  # (eg. window.parent.postMessage({powerboxRequest: {rpcId: myRpcId, query: [{}]}}, "*")
  #
  # The postMessage searches for capabilities in the user's powerbox matching the given query and
  # displays a selection UI to the user.
  # This will then initiate a powerbox interaction with the user, and when it is done, a postMessage
  # callback to the grain will occur. You can listen for such a message like so:
  # window.addEventListener("message", function (event) {
  #   if (event.data.rpcId === myRpcId && !event.data.error) {
  #     // pass event.data.token to your app's server and call SandstormApi.restore() with it
  #   }
  # }, false)

  provide @4 (cap :Capability, requiredPermissions :PermissionSet,
              descriptor :PowerboxDescriptor, displayInfo :PowerboxDisplayInfo);
  # For sessions started with `newRequestSession()`, fulfills the original request. If only one
  # capability was requested, the powerbox will close upon `provide()` being called. If multiple
  # capabilities were requested, then the powerbox remains open and `provide()` may be called
  # repeatedly.
  #
  # If the session was not started with `newRequestSession()`, this method is equivalent to
  # `offer()`. This can be helpful when building a UI that can be used both embedded in the
  # powerbox and stand-alone.

  close @5 ();
  # Closes the session.
  # - For regular sessions, the user will be returned to the home screen.
  # - For powerbox "request" sessions, the user will be returned to the main grain selection list.
  # - For powerbox "offer" sessions, the powerbox will be closed and the user will return to the
  #   offering app.
  #
  # Note that in some cases it is possible for the user to return by clicking "back", so the app
  # should not assume that no further requests will happen.

  openView @6 (view :UiView, path :Text = "", newTab :Bool = false);
  # Navigates the user to some other UiView (from the same grain or another), closing the current
  # session. If `view` is null, navigates back to the the current view, in a new session.
  #
  # `path` is an optional path to jump directly to within the new session. For WebSessions, this
  # is appended to the URL, and may include query (search) and fragment (hash) components, but
  # should never start with '/'. Example: "foo/bar?baz=qux#corge"
  #
  # If `newTab` is true, the new session is opened in a new tab.
  #
  # If the current session is a powerbox session, `openView()` affects the top-level tab, thereby
  # closing the powerbox and the app that initiated the powerbox (unless `newTab` is true).
}

# ========================================================================================
# Sharing and Access Control

struct PermissionDef {
  # Metadata describing a permission bit.

  name @3 :Text;
  # Name of the permission, used as an identifier for the permission in cases where string names
  # are preferred. These names will never be used in Cap'n Proto interfaces, but could show up in
  # HTTP or JSON translations, such as in sandstorm-http-bridge's X-Sandstorm-Permissions header.
  #
  # The name must be a valid identifier (alphanumerics only, starting with a letter) and must be
  # unique among all permissions defined for a particular UiView.

  title @0 :Util.LocalizedText;
  # Display name of the permission, e.g. to display in a checklist of permissions that may be
  # assigned when sharing.

  description @1 :Util.LocalizedText;
  # Prose describing what this permission means, suitable for a tool tip or similar help text.

  obsolete @2 :Bool = false;
  # If true, this permission was relevant in a previous version of the application but should no
  # longer be offered to the user in future sharing actions.
}

using PermissionSet = List(Bool);
# Set of permission IDs, represented as a bitfield.

struct RoleDef {
  # Metadata describing a shareable role.

  title @0 :Util.LocalizedText;
  # Name of the role, e.g. "editor" or "viewer".

  verbPhrase @1 :Util.LocalizedText;
  # Verb phrase describing what users in this role can do with the grain.  Should be something
  # like "can edit" or "can view".  When the user shares the view with others, these verb phrases
  # will be used to populate a drop-list of roles for the user to select.

  description @2 :Util.LocalizedText;
  # Prose describing what this role means, suitable for a tool tip or similar help text.

  permissions @3 :PermissionSet;
  # Permissions which make up this role.  For example, the "editor" role on a document would
  # typically include "read" and "write" permissions.

  obsolete @4 :Bool = false;
  # If true, this role was relevant in a previous version of the application but should no longer
  # be offered to the user in future sharing actions.  The role may still be displayed if it was
  # used to share the view while still running the old version.

  default @5 :Bool = false;
  # If true, this role should be used for any sharing actions that took place using a previous
  # version of the app that did not define any roles. This allows you to seamlessly add roles to
  # an already-deployed app without breaking existing shares. If you do not mark any roles as
  # "default", then such sharing actions will be treated as having an empty permissions set (the
  # user can open the grain, but the grain is told that the user has no permissions).
  #
  # See also `ViewSharingLink.RoleAssignment.none`, below.
}

interface SharingLink {
  # Represents one link in the sharing graph.

  getPetname @0 () -> (name :Util.Assignable(Util.LocalizedText));
  # Name assigned by the sharer to the recipient.
}

interface ViewSharingLink extends(SharingLink) {
  # A SharingLink for a UiView. These links can be attenuated with permissions.

  getRoleAssignment @0 () -> (var :Util.Assignable(RoleAssignment));
  # Returns an Assignable containing a RoleAssignment.

  struct RoleAssignment {
    union {
      none      @0: Void;
      # No role was explicitly chosen. The main case where this happens is when an app defining
      # no roles is shared. Note that "none" means "no role", but does NOT necessarily mean
      # "no permissions". If a default role is defined (see `RoleDef.default`), that will be used.

      allAccess @1 :Void;  # Grant all permissions.
      roleId @2 :UInt16;   # Grant permissions for the given role.
    }

    addPermissions @3 :PermissionSet;
    # Permissions to add on top of those granted above.

    removePermissions @4 :PermissionSet;
    # Permissions to remove from those granted above.
  }
}

# ========================================================================================
# Notifications
#
# TODO(someday): Flesh out the notifications API. Currently this is only used for
#   `SandstormApi.stayAwake()`.

struct NotificationDisplayInfo {
  caption @0 :Util.LocalizedText;
  # Text to display inside the notification box.

  # TODO(someday): Support interactive notifications.
}

interface NotificationTarget {
  # Represents a destination for notifications; usually, a user.
  #
  # TODO(someday): Expand on this and move it into `grain.capnp` when notifications are
  #   fully-implemented.

  addOngoing @0 (displayInfo :NotificationDisplayInfo, notification :OngoingNotification)
             -> (handle :Util.Handle);
  # Sends an ongoing notification to the notification target. `notification` must be persistent.
  # The notification is removed when the returned `handle` is dropped. The handle is persistent.
}

interface OngoingNotification {
  # Callback interface passed to the platform when registering a persistent notification.

  cancel @0 ();
  # Informs the notification creator that the user has requested cancellation of the task
  # underlying this notification.
  #
  # In the case of a `SandstormApi.stayAwake()` notification, after `cancel()` is called, the app
  # will no longer be held awake, so should prepare for shutdown.
  #
  # TODO(someday): We could allow the app to return some text to display to the user asking if
  #   they really want to shut down.
}

# ========================================================================================
# Backup and Restore

struct GrainInfo {
  appId @0 :Text;
  appVersion @1 :UInt32;
  title @2 :Text;
}

# ========================================================================================
# Persistent objects

interface AppPersistent(AppObjectId) {
  # To make an object implemented by your own app persistent, implement this interface.
  #
  # `AppObjectId` is a structure like a URL which identifies a specific object within your app.
  # You may define this structure any way you want. For example, it could literally be a string
  # URL, or it could be a database ID, or it could actually be a serialized representation of an
  # object that isn't actually stored anywhere (like a "data URL").
  #
  # Other apps and external clients will never actually see your `AppObjectId`; it is stored by
  # Sandstorm itself, and clients only see an opaque token. Therefore, you need not encrypt, sign,
  # authenticate, or obfuscate this structure. Moreover, Sandstorm will ensure that only clients
  # who previously saved the object are able to restore it.
  #
  # Note: This interface is called `AppPersistent` rather than just `Persistent` to distinguish it
  #   from Cap'n Proto's `Persistent` interface, which is a more general (and more confusing)
  #   version of this concept. Many things that the general Cap'n Proto `Persistent` must deal
  #   with are handled by Sandstorm, so Sandstorm apps need not think about them. Cap'n Proto
  #   also uses the term `SturdyRef` rather than `ObjectId` -- the major difference is that
  #   `SturdyRef` is cryptographically secure whereas `ObjectId` need not be because it is
  #   protected by the platform.
  #
  # TODO(cleanup): Consider eliminating Cap'n Proto's `Persistent` interface in favor of having
  #   every realm define their own interface. Might actually be less confusing.

  save @0 () -> (objectId :AppObjectId, label :Util.LocalizedText);
  # Saves the capability to disk (if it isn't there already) and then returns the object ID which
  # can be passed to `MainView.restore()` to restore it later.
  #
  # The grain owner will be able to inspect externally-held capabilities via the UI. `label` will
  # be shown there and should briefly describe what this capability represents.
  #
  # Note that Sandstorm compares all object IDs your app produces for equality (using Cap'n Proto
  # canonicalization rules) so that it can recognize when the same object is saved multiple times.
  # `MainView.drop()` will be called when all such references have been dropped by their respective
  # clients.
}

interface MainView(AppObjectId) extends(UiView) {
  # The default (bootstrap) interface exported by a grain to the supervisor when it comes up is
  # actually `MainView`. Only the Supervisor sees this interface. It proxies the `UiView` subset
  # of the interface to the rest of the world, and automatically makes that capability persistent,
  # so that a simple app can completely avoid implementing persistence.
  #
  # `AppObjectId` is a structure type defined by the app which identifies persistent objects
  # within the app, like a URL. See `AppPersistent`, above.

  restore @0 (objectId :AppObjectId) -> (cap :Capability);
  # Restore a live object corresponding to an `AppObjectId`. See `AppPersistent`, above.
  #
  # Apps only need to implement this if they publish persistent capabilities (not including the
  # main UiView).

  drop @1 (objectId :AppObjectId);
  # Indicates that all external persistent references to the given persistent object have been
  # dropped. Depending on the nature of the underlying object, the app may wish to delete it at
  # this point.
  #
  # Note that this method is unreliable. Drop notifications rely on cooperation from the client,
  # who has to explicitly call `drop()` on their end when they discard the reference. Buggy clients
  # may forget to do this. Clients that are destroyed in a fire may have no opportunity to do this.
  # (This differs from live capabilities, which are tied to an ephemeral connection and implicitly
  # dropped when that connection is closed.)
  #
  # That said, Sandstorm gives the grain owner the ability to inspect incoming refs and revoke them
  # explicitly. If all refs to this object are revoked, then Sandstorm will call `drop()`.
  #
  # In some rare cases, `drop()` may be called more than once on the same object. The app should
  # make sure `drop()` is idempotent.
}
