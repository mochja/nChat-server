net = require 'net'
redis = require 'redis'

channels = [ 'default' ]

server = net.createServer (socket) ->
	console.log 'connected client'
	currentChannel = channels[0]

	socket.on 'end', -> console.log 'done'

	socket.on 'data', (buf) ->
		if buf.readInt32BE(0) isnt 1 then socket.end()
		len = buf.readUInt16BE(4)
		if buf.readUInt8(6) isnt 1 then socket.end()
		nick = buf.toString 'utf8', 11
		console.log buf[12], buf
		msg = "there is alot of "+nick+" hello"
		socket.write msg

		client = redis.createClient()
		clientPublish = redis.createClient()
		socket.on 'end', -> client.end(); clientPublish.end()
		client.subscribe currentChannel
		client.on 'message', (channel, message) ->
			console.log message
			socket.write message if channel is currentChannel
		client.on 'subscribe', (channel) ->
			socket.write 'subscribed to '+channel
			socket.removeAllListeners 'data'
			socket.on 'data', (data) ->
				console.log data
				clientPublish.publish currentChannel, nick+": "+data.toString 'utf8'


server.listen 9000