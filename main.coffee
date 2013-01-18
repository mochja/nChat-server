net = require 'net'
redis = require 'redis'
codes = require 'codes'
querystring = require 'querystring'

channels = [ 'default' ]
channelInfo =
	default:
		clients: []

Buffer::readString = (pos) ->
	len = @readUInt32BE pos
	@toString 'utf8', pos+4, len

Buffer::writeUtf16String = (str, pos=0) ->
	@writeUInt32BE str.length*2, pos
	cds = codes.create 'utf16be', 'utf8'
	utf16 = cds.convert(new Buffer(str))
	utf16.copy @, pos+4
	console.log str

server = net.createServer (socket) ->
	console.log 'connected client'
	currentChannel = channels[0]

	socket.on 'end', -> console.log 'done'

	socket.on 'data', (buf) ->
		if buf.readInt32BE(0) isnt 1 then socket.end()
		len = buf.readUInt16BE(4)
		if buf.readUInt8(6) isnt 1 then socket.end()
		nick = buf.toString 'utf8', 11
		msg = "Welcome on nChat #{nick}, u're in #{currentChannel} channel."
		sbuf = new Buffer(msg.length*2+4+4+1)
		sbuf.writeUInt32BE 1, 0
		sbuf.writeUInt8 1, 4
		sbuf.writeUtf16String msg, 5
		socket.write sbuf

		client = redis.createClient()
		clientPublish = redis.createClient()

		socket.on 'end', ->
			console.log 'destroy'
			client.end()
			channelInfo[currentChannel].clients.splice channelInfo[currentChannel].clients.indexOf(nick), 1
			clientPublish.publish currentChannel, JSON.stringify
				type: 'userlist'
				value: channelInfo[currentChannel].clients
			clientPublish.end()

		client.subscribe currentChannel

		client.on 'message', (channel, message) ->
			message = JSON.parse message
			console.log message
			if message.type is 'msg'
				msg = "<p><strong>#{message.value.nick}:</strong><br>#{message.value.msg}</p>"
				msg = msg.replace ';)', '<img src=":/smileys/smiley-wink.png" />'
				buf = new Buffer(msg.length*2+4+4+1)
				buf.writeUInt32BE 1, 0
				buf.writeUInt8 3, 4
				buf.writeUtf16String msg, 5
			else if message.type is 'userlist'
				console.log 'userlist'
				users = message.value
				if users.length is 0
					buf = new Buffer 9
					buf.writeUInt32BE 1, 0
					buf.writeUInt8 2, 4
					buf.writeUInt32BE 0, 5
					return
				len = 0
				for u in users
					len += 4+u.length*2
				buf = new Buffer len+4+4+1
				buf.writeUInt32BE 1, 0
				buf.writeUInt8 2, 4
				buf.writeUInt32BE users.length, 5
				pos = 9
				for u in users
					buf.writeUtf16String u, pos
					pos += u.length*2+4
			socket.write buf if channel is currentChannel

		client.on 'subscribe', (channel) ->
			socket.removeAllListeners 'data'
			channelInfo[currentChannel].clients.push nick
			clientPublish.publish currentChannel, JSON.stringify
				type: 'userlist'
				value: channelInfo[currentChannel].clients
			socket.on 'data', (data) ->
				if data.readInt32BE(0) isnt 1 then socket.end()
				if data.readUInt8(4) is 0x02
					str = JSON.stringify
						type: 'msg'
						value: { nick: nick, msg: data.toString('utf8', 9) }
					clientPublish.publish currentChannel, str


server.listen 9000



