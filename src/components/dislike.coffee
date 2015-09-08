_ = require 'lodash'
React = require 'react'

Button = require './button'

module.exports = React.createFactory React.createClass
  render: ->
    Button _.extend {}, @props,
      active: @props.item.attributes?.dislikes > @props.item.attributes?.likes
      action: 'dislike'
      iconName: 'thumbs-down'
