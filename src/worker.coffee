{ Client } = require 'amqp10'
Promise    = require 'bluebird'
debug      = require('debug')('meshblu-core-worker-amqp:worker')
Redis      = require 'ioredis'
RedisNS     = require '@octoblu/redis-ns'
colors                = require 'colors'
JobLogger  = require 'job-logger'
{ JobManagerRequester } = require 'meshblu-core-job-manager'

class Worker
  constructor: (options) ->
    {
      @amqpUri
      @jobLogQueue
      @jobLogRedisUri
      @jobLogQueue
      @jobLogSampleRate
      @jobTimeoutSeconds
      @maxConnections
      @cacheRedisUri
      @redisUri
      @namespace
      @redisUri
      @requestQueueName
      @responseQueueName
    } = options

    @panic 'missing @redisUri', 2 unless @redisUri?
    @panic 'missing @jobLogQueue', 2 unless @jobLogQueue?
    @panic 'missing @jobLogRedisUri', 2 unless @jobLogRedisUri?
    @panic 'missing @jobLogSampleRate', 2 unless @jobLogSampleRate?
    @panic 'missing @requestQueueName', 2 unless @requestQueueName?
    @panic 'missing @responseQueueName', 2 unless @responseQueueName?

  connect: (callback) =>
    options =
      reconnect:
        forever: false
        retries: 0

    @client = new Client options
    @client.connect @amqpUri
      .then =>
        @client.once 'connection:closed', =>
          throw new Error 'connection to amqp server lost'
        Promise.all [
          @client.createSender()
          @client.createReceiver('meshblu.request')
        ]
      .spread (@sender, @receiver) =>
        callback()
        return true # promises are dumb
      .catch (error) =>
        callback error
      .error (error) =>
        callback error

  panic: (message, exitCode, error) =>
    error ?= new Error(message ? 'generic error')
    console.error colors.red message
    console.error error?.stack
    process.exit exitCode

  run: (callback) =>
    @connect (error) =>
      return callback error if error?

      jobLogger = new JobLogger
        client: new Redis @jobLogRedisUri, dropBufferSupport: true
        indexPrefix: 'metric:meshblu-core-protocol-adapter-amqp'
        type: 'meshblu-core-protocol-adapter-amqp:request'
        jobLogQueue: @jobLogQueue

      @jobManager = new JobManagerRequester {
        @namespace
        @redisUri
        maxConnections: 2
        @jobTimeoutSeconds
        @jobLogSampleRate
        @jobTimeoutSeconds
        @requestQueueName
        @responseQueueName
        queueTimeoutSeconds: @jobTimeoutSeconds
        maxConnections: 2
        @redisUri
        @namespace
      }

      @jobManager.once 'error', (error) =>
        @panic 'fatal job manager error', 1, error

      @jobManager._do = @jobManager.do
      @jobManager.do = (request, callback) =>
        @jobManager._do request, (error, response) =>
          jobLogger.log { error, request, response }, (jobLoggerError) =>
            return callback jobLoggerError if jobLoggerError?
            callback error, response

      @jobManager.start (error) =>
        return callback error if error?
        @receiver.on 'message', (message) =>
          debug 'message received:', message
          job = @_amqpToJobManager message
          debug 'job:', job

          @jobManager.do job, (error, response) =>
            debug 'response received:', response, error
            return @_emitError {error, message} if error?
            return @_emitError {error: new Error ('No Response'), message} unless response?
            options =
              properties:
                correlationId: message.properties.correlationId
                subject: message.properties.replyTo
              applicationProperties:
                code: response.code || 0

            debug 'sender options', options
            @sender.send response.rawData, options
        callback()

  panic: (message, exitCode, error) =>
    error ?= new Error('generic error')
    console.error message
    console.error error.stack
    process.exit(exitCode ? 1)


  _emitError: ({error, message}) =>
    options =
      properties:
        correlationId: message.properties.correlationId
        subject: message.properties.replyTo
      applicationProperties:
        code: error.code || 500

    debug 'sending error', options
    @sender.send JSON.stringify(error.stack), options

  stop: (callback) =>
    @jobManager.stop =>
      @client.disconnect()
        .then callback
        .catch callback

  _amqpToJobManager: (message) =>
    job =
      metadata: message.applicationProperties
      rawData: message.body

module.exports = Worker
