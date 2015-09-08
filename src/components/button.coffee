React = require 'react'

{DOM} = React

module.exports = React.createFactory React.createClass
  onClick: (e) ->
    e.preventDefault()
    url = e?.currentTarget?.href
    return unless url
    url += '.json'
    console.log 'url', url
    @props.request.get url, {}, (err, data) =>
      item = data?.data?[0]
      if item?._id
        console.log 'sending update', item._id
        @props.Repository.update item._id, _.extend {},
          @props.Repository.getLatest(item._id)
          attributes: item.attributes
      console.log 'like/dislike data', data, err, item?._id

  render: ->
    DOM.a
      className: "stream-item-control #{if @props.active then 'active' else ''}"
      href: "/admin/item/#{@props.item._id}/#{@props.action}"
      onClick: @onClick
    ,
      DOM.em
        className: "glyphicon glyphicon-#{@props.iconName}"
