_ = require 'lodash'
Promise = require 'when'

# pass -1 to +1 and will return a strength from 0-1
weight = (x) ->
  1 - 1 / (x * x * 10 + 1)

module.exports = (System) ->
  Identity = System.getModel 'Identity'
  ActivityItem = System.getModel 'ActivityItem'

  getItem = (id) ->
    deferred = Promise.defer()
    ActivityItem
    .where
      _id: id
    .findOne (err, item) ->
      return deferred.reject err if err
      deferred.resolve item
    deferred.promise

  likeOrDislikeObject = (item, dir) ->
    item.liked = dir == 1
    item.disliked = dir == -1
    attr = item.attributes ? {}
    attr.likes = 0 unless attr.likes > 0
    attr.dislikes = 0 unless attr.dislikes > 0
    if dir == 1
      attr.likes++
    else if dir == -1
      attr.dislikes++
    attr.rated = false
    item.attributes = attr
    item.markModified 'attributes'
    item

  models = {}
  postInit = ->
    toRate = System.getGlobal 'public.activityItem.populate'
    return unless toRate
    for k, v of toRate
      model = System.getModel v
      models[k] = model if model

  getAndLike = (Model, id, dir) ->
    deferred = Promise.defer()
    Model
    .where
      _id: id
    .findOne (err, obj) ->
      return deferred.reject err if err
      return deferred.resolve() unless obj
      likeOrDislikeObject obj, dir
      deferred.resolve obj
    deferred.promise

  testGuid = 'twitter-621197577573281792'
  likeOrDislikeItem = (dir, req, res, next) ->
    getItem req.params.id
    .then (item) ->
      if item?.guid == testGuid
        console.log 'likeOrDislike'
      return unless item
      likeOrDislikeObject item, dir
      if dir == 1
        item.attributes.dislikes = 0
      else if dir == -1
        item.attributes.likes = 0
      Promise.all _.map models, (Model, field) ->
        ids = item.attributes?[field] ? []
        Promise.all _.map ids, (id) ->
          getAndLike Model, id, dir
          .then (obj) ->
            System.do "#{field}.save", obj
      .then ->
        console.log 'hopefully re-score', item?.guid #if String(item.guid) == testGuid
        item.attributes.rated = false
        System.do 'activityItem.save', item
      .catch (err) ->
        console.log 'WAT', err.stack ? err
    .then likeOrDislikeIdentity
    .then (item) ->
      return next() unless item
      res.send
        data: [item]
    .catch (err) ->
      console.log 'wat', err.stack ? err
      next err

  likeOrDislikeIdentity = (item) ->
    deferred = Promise.defer()
    id = item.identity?._id ? item.identity
    Identity
    .where
      _id: id
    .findOne (err, identity) ->
      return deferred.reject err if err
      return deferred.reject new Error 'No identity?' unless identity
      identity.lastOutboundInteraction = identity.lastInteraction = new Date()
      likes = identity.attributes?.likes ? 0
      dislikes = identity.attributes?.dislikes ? 0
      if item.attributes.likes > item.attributes.dislikes
        likes++
      else
        dislikes++
      attributes = _.extend {}, (identity.attributes ? {}),
        likes: likes
        dislike: dislikes
        rating: likes - dislikes
        rated: true
      identity.markModified 'attributes'
      identity.save (err) ->
        return deferred.reject err if err
        deferred.resolve item
    deferred.promise

  like = (req, res, next) ->
    likeOrDislikeItem 1, req, res, next

  dislike = (req, res, next) ->
    likeOrDislikeItem -1, req, res, next

  # bePopulated = (item, field) ->
  #   return Promise() if item.populated field
  #   deferred = Promise.defer()
  #   item.populate field, (err) ->
  #     return deferred.reject err if err
  #     deferred.resolve()
  #   deferred.promise

  scoreThenSave = (item, fields) ->
    console.log 'scoreThenSave', item.attributes?.rated if item.guid == testGuid
    return item if item.attributes?.rated
    deferred = Promise.defer()
    scoreObject(fields)(item)
    .then ->
      item.save (err) ->
        console.log 'scoreThenSave failed to save', err if err
        return deferred.reject err if err
        deferred.resolve item
    deferred.promise

  scoreRefs = (item, fields = []) ->
    # console.log 'scoreRefs', fields if item.guid == testGuid
    promise = if fields.length > 0
      System.do 'activityItem.populate', item
    else
      Promise()

    promise
    .then ->
      Promise.all _.map fields, (field) ->
        # bePopulated item, field
        # .then ->
        subitems = if item.fullAttributes[field] instanceof Array
          item.fullAttributes[field]
        else
          [item.fullAttributes[field]]
        Promise.all _.map subitems, (subitem) ->
          # console.log 'score subitem', subitem unless subitem.save?
          scoreThenSave subitem

  scoreItem = (item) ->
    scoreObject(Object.keys models)(item)
  scoreItem.precedence = 100

  scoreObject = (fields = []) ->
    (item) ->
      # console.log 'scoreObject', fields if item.guid == testGuid
      return item if item?.attributes?.rated
      throw new Error 'item required' unless item
      scoreRefs item, fields
      .then (subscores) ->
        subscores = _.flatten subscores
        # console.log 'subscores', _.map subscores, (s) ->
        #   s?.attributes?.score ? ''
        attr = item.attributes ? {}
        # attr.ratings = {} unless attr.ratings
        scores = [0]
        if attr.likes or attr.dislikes
          likes = attr.likes ? 0
          dislikes = attr.dislikes ? 0
          inertia = 3
          total = likes + dislikes + inertia
          force = if likes > dislikes
            likes / total
          else if dislikes > likes
            dislikes / total
          else
            0
          scores.push force * (if likes > dislikes then 100 else -100)
        for k, v of attr.ratings
          scores.push v
        for subscore in subscores
          if subscore?.attributes?.score
            scores.push subscore.attributes.score
        scores.push 100 if attr.liked
        scores.push -100 if attr.disliked
        sum = _.reduce scores, ((memo, item) -> memo + item), 0
        attr.score = sum / scores.length
        attr.rated = true
        item.attributes = attr
        if item.markModified?
          item.markModified 'attributes'
        # console.log 'done with', scores
        item

  rescore = (req, res, next) ->
    getItem req.params.id
    .then (item) ->
      return unless item
      item.attributes = {} unless item.attributes
      item.attributes.rated = false
      System.do 'activityItem.save', item
    .done (item) ->
      return next() unless item
      res.redirect "/admin/item/#{item._id}/show"
    , (err) ->
      console.log 'wat', err.stack ? err
      next err

  routes:
    admin:
      '/admin/item/:id/rescore': 'rescore'
      '/admin/item/:id/like': 'like'
      '/admin/item/:id/dislike': 'dislike'

  handlers:
    like: like
    dislike: dislike
    rescore: rescore

  globals:
    public:
      activityItem:
        controls:
          'kerplunk-rating:like': true
          'kerplunk-rating:dislike': true
  events:
    init:
      post: postInit
    activityItem:
      save:
        pre: scoreItem
    characteristic:
      save:
        pre: scoreObject()
    topic:
      save:
        pre: scoreObject()
