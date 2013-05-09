_u      = require 'underscore'
icecast = require "icecast"

module.exports = class Shoutcast
    constructor: (@stream,@opts) ->
        @id = null
        @socket = null
        
        @stream.log.debug "request is in Shoutcast output", stream:@stream.key
        
        if @opts.req && @opts.res
            # -- startup mode...  sending headers -- #
            
            @reqIP      = @opts.req.connection.remoteAddress
            @reqPath    = @opts.req.url
            @reqUA      = _u.compact([@opts.req.param("ua"),@opts.req.headers?['user-agent']]).join(" | ")
            @offset     = @opts.req.param("offset") || -1
            
            @opts.res.chunkedEncoding = false
            @opts.res.useChunkedEncodingByDefault = false
            
            @headers = 
                "Content-Type":         
                    if @stream.opts.format == "mp3"         then "audio/mpeg"
                    else if @stream.opts.format == "aac"    then "audio/aacp"
                    else "unknown"
                "icy-name":             @stream.StreamTitle
                "icy-url":              @stream.StreamUrl
                "icy-metaint":          @stream.opts.meta_interval
                        
            # write out our headers
            @opts.res.writeHead 200, @headers
            @opts.res._send ''
            
            @socket = @opts.req.connection
            
            process.nextTick =>     
                # -- send a preroll if we have one -- #
        
                if @stream.preroll && !@req.param("preskip")
                    @stream.log.debug "making preroll request"
                    @stream.preroll.pump @socket, => @connectToStream()
                else
                    @connectToStream()       
            
        else if @opts.socket
            # -- socket mode... just data -- #
            
            @socket = @opts.socket
            process.nextTick => @connectToStream()
        
        # register our various means of disconnection
        @socket.on "end",   => @disconnect()
        @socket.on "close", => @disconnect()
        
    #----------
    
    disconnect: (force=false) ->
        if force || @socket.destroyed
            @source?.disconnect()            
            @socket?.end() unless (@socket?.destroyed)
    
    #----------
    
    connectToStream: ->
        unless @socket.destroyed
            @source = @stream.listen @, offset:@offset, pump:true
            
            # -- create an Icecast creator to inject metadata -- #
            
            @ice = new icecast.Writer @stream.opts.meta_interval            
            @ice.queue StreamTitle:@stream.StreamTitle, StreamUrl:@stream.StreamUrl
        
            @metaFunc = (data) =>
                @ice.queue data if data.StreamTitle

            @ice.pipe(@socket)
            
            # -- pipe source audio to icecast -- #
            
            @source.pipe @ice
            @source.on "meta", @metaFunc
        
    #----------
            
