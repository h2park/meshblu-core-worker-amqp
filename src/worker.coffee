{ Client } = require 'amqp10'
Promise    = require 'bluebird'
debug      = require('debug')('meshblu-core-worker-amqp:worker')
Redis      = require 'ioredis'
RedisNS     = require '@octoblu/redis-ns'
JobLogger  = require 'job-logger'
{ JobManagerRequester } = require 'meshblu-core-job-manager'

class Worker
  constructor: (options)->
    {
      @jobTimeoutSeconds
      @jobLogQueue
      @jobLogRedisUri
      @jobLogSampleRate
      @amqpUri
      @maxConnections
      @cacheRedisUri
      @redisUri
      @namespace
      @requestQueueName
      @responseQueueName
    } = options

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
        @requestQueueName
        @responseQueueName
        queueTimeoutSeconds: @jobTimeoutSeconds
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
            return if error?
            debug 'response received:', response

            options =
              properties:
                correlationId: message.properties.correlationId
                subject: message.properties.replyTo
              applicationProperties:
                code: response.code || 0

            debug 'sender options', options
            @sender.send response.rawData, options

  panic: (message, exitCode, error) =>
    error ?= new Error('generic error')
    console.error message
    console.error error?.stack
    process.exit exitCode

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
