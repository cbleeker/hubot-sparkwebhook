{Robot, Adapter, TextMessage} = require 'hubot'
https = require 'http'
CiscoSparkClient = require('node-sparkclient')
sparkclient = new CiscoSparkClient(process.env.CISCOSPARK_ACCESS_TOKEN)
request = require 'request'
class SparkWebhook extends Adapter
  constructor: (robot) ->
    super robot
    @me ={}
    self = @
    @getMe (err,me) ->
      if (err)
        self.logError "Error: "+JSON.stringify(err)
      else
        self.me = me

  log: console.log.bind console
  logError: console.error.bind console

  ###################################################################
  # Communicating back to the Cisco Spark room.
  ###################################################################
  send: (envelope, strings...) ->
    roomId = envelope.room
    strings.forEach (str) =>
      if @isImageDocURL(str)
        messageParams = {}  
        messageParams.file = str
        sparkclient.createMessage roomId, null, messageParams, (err, response) ->
          if err
            self.logError "Error: "+JSON.stringify(err)
      else
        messageParams = {}  
        messageParams.markdown = true
        sparkclient.createMessage roomId,str, messageParams, (err, response) ->
          if err
            self.logError "Error: "+JSON.stringify(err)

  reply: (envelope, strings...) ->
    @log "Sending reply"
    user_name = envelope.user?.name || envelope?.name
    strings.forEach (str) =>
      @send envelope, "#{user_name}: #{str}"

  ###################################################################
  # The main function
  ###################################################################
  run: ->
    self = @

    # Listen to incoming webhooks from CiscoSpark
    self.robot.router.post "/hubot/ciscospark/incoming", (req, res) ->
      self.log("Received Cisco Spark Message")
      IncomingMessage = req.body
      # Make sure it is a message created event and make sure it's not from the bot.
      if IncomingMessage.resource == 'messages' && IncomingMessage.event == 'created' && IncomingMessage.data.personId != self.me.id
          sparkclient.getMessage IncomingMessage.data.id, (err, messageDetail) ->
            if err
              self.logError "Error: "+JSON.stringify(err)
            else
              text = null
              if (messageDetail.mentionedPeople) #bot accounts have to be mentioned in cisco spark
                text = self.robot.name+" "+self.stripMention(messageDetail.html)
              else # must be a 1:1 room
                text = self.robot.name+" "+messageDetail.text
              author =  {}
              author.room = messageDetail.roomId
              author.name =  messageDetail.personEmail
              if text and author
                self.receive new TextMessage(author, text)

      # send back an empty reply to the incoming webhook.
      res.end ""

    # Tell Hubot we are connected so it can load scripts
    @log "Successfully 'connected' as", self.robot.name
    self.emit "connected"

  stripMention: (mentionText) ->
    mentionRegex = /(.*)\<spark-mention .*\/spark-mention\>(.*)/i
    match = mentionText.match(mentionRegex)
    if match && match.length > 1
      return match[1].trim()+match[2].trim()

  isImageDocURL: (url) ->
    imageDocRegex = /http.*(jpg|jpeg|png|gif|doc|pdf|docx|ppt)$/i
    match = url.match(imageDocRegex)
    if  match && match.length > 1
      return true
    else
      return false

  getMe: (callback) ->
    request.get "https://api.ciscospark.com/v1/people/me",
       headers: Authorization : "Bearer "+process.env.CISCOSPARK_ACCESS_TOKEN,
       (err,response,body) ->
         if err
           callback err
         else
           callback null,JSON.parse(body)


exports.use = (robot) ->
  new SparkWebhook robot

exports.SparkWebhook = SparkWebhook
