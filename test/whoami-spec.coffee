Worker      = require '../src/worker'
MeshbluAmqp = require 'meshblu-amqp'
RedisNS     = require '@octoblu/redis-ns'
Redis       = require 'ioredis'
async       = require 'async'
UUID        = require 'uuid'
{ JobManagerResponder }  = require 'meshblu-core-job-manager'

describe 'whoami', ->
  beforeEach ->
    queueId = UUID.v4()
    @requestQueueName = "test:request:queue:#{queueId}"
    @responseQueueName = "test:response:queue:#{queueId}"
    @namespace = 'ns'
    @redisUri = 'redis://localhost'

  beforeEach (done) ->
    @jobManager = new JobManagerResponder {
      @redisUri
      @namespace
      maxConnections: 1
      jobTimeoutSeconds: 1
      queueTimeoutSeconds: 1
      jobLogSampleRate: 0
      @requestQueueName
      @responseQueueName
    }

    @jobManager.start done

  afterEach (done) ->
    @jobManager.stop done

  beforeEach ->
    @worker = new Worker {
      amqpUri: 'amqp://meshblu:judgementday@127.0.0.1'
      jobTimeoutSeconds: 1
      jobLogRedisUri: @redisUri
      jobLogQueue: 'sample-rate:0.00'
      jobLogSampleRate: 0
      redisUri: @redisUri
      cacheRedisUri: @redisUri
      namespace: @namespace
      @requestQueueName
      @responseQueueName
    }

    @worker.run (error) =>
      throw error if error?

  afterEach (done) ->
    @worker.stop done
    return # nothing

  beforeEach (done) ->
    @client = new MeshbluAmqp uuid: 'some-uuid', token: 'some-token', hostname: 'localhost'
    @client.connect done
    return # avoid returning async

  beforeEach (done) ->
    @jobManager.do (@jobManagerRequest, callback) =>
      response =
        metadata:
          responseId: @jobManagerRequest.metadata.responseId
        data: { whoami:'somebody' }
        code: 200

      callback null, response

    @client.whoami (error, @data) =>
      done error

    return # avoid returning async

  it 'should create a @jobManagerRequest', ->
    expect(@jobManagerRequest.metadata.jobType).to.deep.equal 'GetDevice'

  it 'should give us a device', ->
    expect(@data).to.exist
