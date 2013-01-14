net = require 'net'
redis = require 'redis'
codes = require 'codes'
querystring = require 'querystring'

channels = [ 'default' ]
channelInfo =
	default:
		clients: ['user1']

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
			clientPublish.publish currentChannel, querystring.stringify
				type: 'userlist'
				value: channelInfo[currentChannel].clients
			client.end()
			clientPublish.end()
			channelInfo[currentChannel].clients.slice channelInfo[currentChannel].clients.indexOf(nick), 1

		client.subscribe currentChannel

		client.on 'message', (channel, message) ->
			message = querystring.parse message
			console.log message
			if message.type is 'msg'
				buf = new Buffer(message.value.length*2+4+4+1)
				buf.writeUInt32BE 1, 0
				buf.writeUInt8 1, 4
				buf.writeUtf16String message.value, 5
			else if message.type is 'userlist'
				users = message.value
				len = 0
				for u in users
					len += 4+u.length*2
				buf = new Buffer len+4+1
				buf.writeUInt32BE 1, 0
				buf.writeUInt8 2, 4
				pos = 5
				for u in users
					console.log u
					buf.writeUtf16String u, pos
					pos += u.length*2+4
				console.log pos, len
			console.log buf
			socket.write buf if channel is currentChannel

		client.on 'subscribe', (channel) ->
			socket.removeAllListeners 'data'
			channelInfo[currentChannel].clients.push nick
			clientPublish.publish currentChannel, querystring.stringify
				type: 'userlist'
				value: channelInfo[currentChannel].clients
			socket.on 'data', (data) ->
				console.log data
				console.log channelInfo[currentChannel].clients
				if data.readInt32BE(0) isnt 1 then socket.end()
				if data.readUInt8(4) is 0x02
					str = querystring.stringify
						type: 'msg'
						value: nick+": "+data.toString 'utf8', 9
					clientPublish.publish currentChannel, str


server.listen 9000



