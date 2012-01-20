DEFAULT_MODEL =
  organisation: {}
  mapping:
    'iati-identifier':
      type: 'value'
      'iati-field': 'iati-identifier'
      label: 'IATI Identifier'
    from:
      type: 'compound'
      label: 'Spender'
      fields:
        'bodge-job':
          column: 'recipient'
        'something-else':
          column: 'dept_id'
    to:
      type: 'value'
      label: 'Recipient'

DEFAULT_FIELD_SETUP =
  'iati-identifier':
    type: 'value'
    label: 'IATI Identifier'
  'title':
    type: 'value'
    label: 'Title'
  'description':
    type: 'value'
    label: 'Description'
  'sectors':
    type: 'compound'
    label: 'Sectors'
    fields: ['code', 'vocab', 'text']

DIMENSION_META =
  iati_identifier:
    fixedDataType: true
    helpText: '''
              The unique IATI Identifier for your project.
              '''
  title:
    fixedDataType: true
    helpText: '''
              The title of your project.
              '''
    label: 'Title'
  description:
    fixedDataType: true
    helpText: '''
              The description of your project.
              '''
  amount:
    fixedDataType: true
    helpText: '''
              The most important field in the dataset. Please choose which of
              the columns in your dataset represents the value of the spending,
              and how you'd like it to be displayed.
              '''
  sectors:
    fixedDataType: true
    field_type: 'compound'
    fields: '1,2,3,4'
    helpText: '''
              The sectors in your dataset
              '''

FIELDS_META =
  label:
    required: true

String::dasherize = ->
  this.replace /_/g, "-"

util =
  # Turns a nested object into a flat mapping with PHP-like query string
  # parameters as keys.
  #
  # Examples
  #
  #   # Flatten a nested object structure
  #   flattenObject({'one': {'two': 'foo'}})
  #   # => Returns {'one[two]': 'foo'}
  #
  #   # Flatten an object containing arrays
  #   flattenObject({'list': [1,2,3]})
  #   # => Returns {'list[]': [1,2,3]}
  #
  # Returns the flattened object
  flattenObject: (obj) ->
    flat = {}

    pathStr = (path) ->
      ary = [path[0]]
      ary = ary.concat("[#{p}]" for p in path[1..-1])
      ary.join ''

    walk = (path, o) ->
      for key, value of o
        newpath = $.extend([], path)
        newpath.push(key)

        if $.type(value) is 'object'
          walk newpath, value
        else
          if $.type(value) is 'array'
            newpath.push ''

          flat[pathStr(newpath)] = value

    walk([], obj)
    flat

class Widget extends Delegator
  deserialize: (data) ->

class UniqueKeyWidget extends Widget
  events:
    'span click': 'onKeyClick'

  deserialize: (data) ->
    uniq = (data['dataset']?['unique_keys'] or [])

    availableKeys = []
    for k, v of data['mapping']
      if v['type'] isnt 'value'
        for fk, fv of v['fields']
          availableKeys.push("#{k}.#{fk}")
      else
        availableKeys.push(k)

    @keys = ({'name': k, 'used': k in uniq} for k in availableKeys)
    this.render()

  promptAddDimensionNamed: (props, thename) ->
    return false

  render: ->
    @element.html($.tmpl('tpl_unique_keys', {'keys': @keys}))

  onKeyClick: (e) ->
    idx = @element.find('span').index(e.currentTarget)
    @keys[idx]['used'] = not @keys[idx]['used']
    this.render()

    # Futzing with the DOM and adding form fields does not trigger form change
    # events, so we have to trigger them manually.
    @element.parents('form').first().change()

class DimensionWidget extends Widget
  events:
    '.add_field click': 'onAddFieldClick'
    '.field_switch_constant click': 'onFieldSwitchConstantClick'
    '.field_switch_column click': 'onFieldSwitchColumnClick'
    '.field_rm click': 'onFieldRemoveClick'
    '.delete_dimension click': 'onDeleteDimensionClick'
    '.iatifield change' : 'onIATIFieldChange'

  constructor: (name, container, options) ->
    @name = name
    el = $("<fieldset class='dimension' data-dimension-name='#{@name}'>
            </fieldset>").appendTo(container)

    super el, options

    @id = "#{@element.parents('.modeleditor').attr('id')}_dim_#{@name}"
    @element.attr('id', @id)

    @meta = DIMENSION_META[@name] or {}

  deserialize: (data) ->
    @data = data['mapping']?[@name] or {}

    # Prepopulate field-less non-value dimensions with a label field
    if @data.type isnt 'value' and 'fields' not of @data
      @data.fields = {'label': {'datatype': 'string'}}

    @element.html($.tmpl('tpl_dimension', this))
    @element.trigger('fillColumnsRequest', [@element.find('select.column')])
    @element.trigger('fillIATIfieldsRequest', [@element.find('select.iatifield')])

    formObj = {'mapping': {}}
    formObj['mapping'][@name] = @data

    for k, v of util.flattenObject(formObj)
      @element.find("[name=\"#{k}\"]").val(v)

  formFieldPrefix: (fieldName) =>
    "mapping[#{@name}][fields][#{fieldName}]"

  formFieldRequired: (fieldName) =>
    FIELDS_META[fieldName]?['required'] or false

  onAddFieldClick: (e) ->
    name = prompt("Field name:").trim()
    row = this._makeFieldRow(name)
    row.appendTo(@element.find('tbody'))
    @element.trigger('fillColumnsRequest', [row.find('select.column')])
    return false

  onDeleteDimensionClick: (e) ->
    $(e.currentTarget).parents('fieldset').first().remove()
    @element.parents('form').first().change()
    return false

  onIATIFieldChange: (e) ->
    @element.parents('form').first().change()
    thisfield = $(e.currentTarget).val()
    @element.find('tbody tr').remove()
    if (DEFAULT_FIELD_SETUP[thisfield]['type'] == 'compound')
        thisfieldsfields = (DEFAULT_FIELD_SETUP[thisfield]['fields'])
        for k, v of thisfieldsfields
            row = this._makeFieldRow(v)
            row.appendTo(@element.find('tbody'))
            @element.trigger('fillColumnsRequest', [row.find('select.column')])
    else
        w = new DimensionWidget(thisfield, @dimsEl)
        @widgets.push(w)
        return w
        @element.empty()
        @element.html($.tmpl('tpl_dimension', this))
        @element.trigger('fillColumnsRequest', [@element.find('select.column')])
        @element.trigger('fillIATIfieldsRequest', [@element.find('select.iatifield')])
    return false

  onFieldRemoveClick: (e) ->
    $(e.currentTarget).parents('tr').first().remove()
    @element.parents('form').first().change()
    return false

  onFieldSwitchConstantClick: (e) ->
    curRow = $(e.currentTarget).parents('tr').first()
    row = this._makeFieldRow(curRow.data('field-name'), true)
    curRow.replaceWith(row)
    @element.parents('form').first().change()
    return false

  onFieldSwitchColumnClick: (e) ->
    curRow = $(e.currentTarget).parents('tr').first()
    row = this._makeFieldRow(curRow.data('field-name'), false)
    curRow.replaceWith(row)
    @element.trigger('fillColumnsRequest', [row.find('select.column')])
    @element.parents('form').first().change()
    return false
    
  promptAddDimensionNamed: (props, thename) ->
    return false

  _makeFieldRow: (name, constant=false) ->
    tplName = if constant then 'tpl_dimension_field_const' else 'tpl_dimension_field'
    required =
    $.tmpl tplName,
      'fieldName': name
      'prefix': this.formFieldPrefix
      'required': this.formFieldRequired

class DimensionsWidget extends Delegator
  events:
    '.add_value_dimension click': 'onAddValueDimensionClick'
    '.add_compound_dimension click': 'onAddCompoundDimensionClick'

  constructor: (element, options) ->
    super

    @widgets = []
    @dimsEl = @element.find('.dimensions').get(0)

  addDimension: (name) ->
    w = new DimensionWidget(name, @dimsEl)
    @widgets.push(w)
    return w

  removeDimension: (name) ->
    idx = null

    for w in @widgets
      if w.name is name
        idx = @widgets.indexOf(w)
        break

    if idx isnt null
      @widgets.splice(idx, 1)[0].element.remove()

  deserialize: (data) ->
    return if @ignoreParent

    dims = data['mapping'] or {}
    toRemove = []

    for widget in @widgets
      if widget.name of dims
        widget.deserialize(data)
        delete dims[widget.name]
      else
        toRemove.push(widget.name)

    # Remove any widgets not in dims
    for name in toRemove
      this.removeDimension(name)

    # Any keys left in dims need to be added
    for name, obj of dims
      this.addDimension(name).deserialize(data)

  promptAddDimension: (props) ->
    name = prompt("Give a unique name for your new dimension (letters and numbers, no spaces):")
    return false unless name
    data = {'mapping': {}}
    data['mapping'][name] = props
    this.addDimension(name.trim()).deserialize(data)

  promptAddDimensionNamed: (thename, props) ->
    alert("Column \"" + thename + "\" has been added.")
    name = thename
    return false unless name
    data = {'mapping': {}}
    data['mapping'][name] = props
    this.addDimension(name.trim()).deserialize(data)

  onAddValueDimensionClick: (e) ->
    this.promptAddDimension({'type': 'value'})
    return false

  onAddCompoundDimensionClick: (e) ->
    this.promptAddDimension({'type': 'compound'})
    return false

class ModelEditor extends Delegator
  widgetTypes:
    '.unique_keys_widget': UniqueKeyWidget
    '.dimensions_widget': DimensionsWidget

  events:
    'modelChange': 'onModelChange'
    'fillColumnsRequest': 'onFillColumnsRequest'
    'fillIATIfieldsRequest': 'onFillIATIfieldsRequest'
    '.steps > ul > li click': 'onStepClick'
    '.steps > ul > li > ul > li click': 'onStepDimensionClick'
    '.forms form submit': 'onFormSubmit'
    '.forms form change': 'onFormChange'
    '#showdebug click': 'onShowDebugClick'
    '.add_data_field click': 'onAddDataFieldClick'
    'doFieldSelectors' : 'onDoFieldSelectors'

  constructor: (element, options) ->
    super
    @data = $.extend(true, {}, DEFAULT_MODEL)
    @widgets = []

    @form = $(element).find('.forms form').eq(0)

    @id = @element.attr('id')
    if not @id?
      @id = Math.floor((Math.random()*0xffffffff)).toString(16)
      @element.attr('id', @id)

    # Precompile templates
    @element.find('script[type="text/x-jquery-tmpl"]').each  ->
      $(this).template($(this).attr('id'))

    # Initialize column select boxes
    @options.columns.unshift('')
    @element.find('select.iatifield').each ->
      $(this).trigger('fillColumnsRequest', [this])

    # Initialize iati select boxes
    @options.iatifields.unshift('')
    @element.find('select.iatifield').each ->
      $(this).trigger('fillIATIfieldsRequest', [this])

    # Initialize widgets
    for selector, ctor of @widgetTypes
      @widgets.push(new ctor(e)) for e in @element.find(selector).get()

    @element.trigger 'modelChange'

    this.setStep 0

  setStep: (s) ->
    $(@element).find('.steps > ul > li')
      .removeClass('active')
      .eq(s).addClass('active')

    $(@element).find('.forms div.formpart').hide().eq(s).show()

  onStepClick: (e) ->
    idx = @element.find('.steps > ul > li').index(e.currentTarget)
    this.setStep idx
    return false

  onAddDataFieldClick: (e) ->
    thevar = $(e.currentTarget).text() 
    for w in @widgets
        w.promptAddDimensionNamed(thevar,{'type': 'value','column':thevar,'label':thevar})
    @data = @form.serializeObject()
    @element.trigger 'modelChange'
    $(e.currentTarget).removeClass('add_data_field available').addClass('unavailable')

  onShowDebugClick: (e) ->
    if $('#debug').hasClass('debug-shown')
      $('#debug').slideUp().removeClass('debug-shown')
    else
      $('#debug').slideDown().addClass('debug-shown')
    return false

  onFormChange: (e) ->
    return if @ignoreFormChange

    @data = @form.serializeObject()
    @form.find('.column').each -> 
        columnname = ($(this).val())
        $('#user_columns ul li a').each ->
            if ($(this).text()) == columnname
                $(this).removeClass('available').addClass('unavailable')
    
    @element.trigger('doFieldSelectors', 'iatifield')
    @element.trigger('doFieldSelectors', 'column')
        
    @ignoreFormChange = true
    @element.trigger 'modelChange'
    @ignoreFormChange = false

    
  onDoFieldSelectors: (e) ->
    $('#' + e + 's ul li a').each ->
        if ($(this).hasClass('unavailable'))
            $(this).removeClass('unavailable')
            $(this).addClass('available')
    @form.find('.' + e).each -> 
        iatiname = ($(this).val())
        $('#' + e + 's ul li a').each ->
            if ($(this).text() == iatiname)
                $(this).removeClass('available')
                $(this).addClass('unavailable')

  onFormSubmit: (e) ->
    return false

  onModelChange: () ->
    # Populate straightforward bits
    for k, v of util.flattenObject(@data)
      # FIXME? this may not deal with complex form elements such as radio
      # buttons or <select multiple>.
      @form.find("[name=\"#{k}\"]").val(v)

    # Send updated model copy to each subcomponent, as more complex
    # components may not have been correctly filled out by the above.
    for w in @widgets
      w.deserialize($.extend(true, {}, @data))

    # Update dimension list in sidebar
    dimNames = (k for k, v of @data['mapping'])
    @element.find('.steps ul.steps_dimensions').html(
      ('<li><a href="#' + "m1_dim_#{n}" + '">' + "#{n.dasherize()}</a>" for n in dimNames).join('\n')
    )

    $('#debug').text(JSON.stringify(@data, null, 2).dasherize())


  onFillColumnsRequest: (elem) ->
    $(elem).html(
      ("<option name='#{x}'>#{x}</option>" for x in @options.columns).join('\n')
    )
  onFillIATIfieldsRequest: (elem) ->
    $(elem).html(
      ("<option name='#{x}'>#{x}</option>" for x in @options.iatifields).join('\n')
    )

$.plugin 'modelEditor', ModelEditor

this.ModelEditor = ModelEditor
