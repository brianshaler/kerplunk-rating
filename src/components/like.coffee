_ = require 'lodash'
React = require 'react'

Button = require './button'

module.exports = React.createFactory React.createClass
  render: ->
    Button _.extend {}, @props,
      active: @props.item.attributes?.likes > @props.item.attributes?.dislikes
      action: 'like'
      iconName: 'thumbs-up'
