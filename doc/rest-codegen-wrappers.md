# REST wrapper integration in generated clients

## Scope

`d_rocket_builder` previously generated clients that always called the global
`dRest.client`. That made per-client HTTP pipelines impossible: two generated
clients could not use different transports or resilience policies.

## New contract

Generated clients keep the existing API:

```dart
final client = createApiClient();
```

They also accept an optional `RestClientConfig`:

```dart
final client = createApiClient(
  config: RestClientConfig(
    client: HttpPackageClient(),
    wrappers: <HttpClientWrapper>[
      (inner) => HmacSignedHttpClient(
        inner: inner,
        signer: HmacSha256Signer(utf8.encode('secret')),
      ),
      (inner) => RetryingHttpClient(
        inner: inner,
        policy: ExponentialBackoffRetryPolicy(maxAttempts: 3),
      ),
      (inner) => CircuitBreakerHttpClient(inner: inner),
      (inner) => EtagCacheHttpClient(inner: inner),
      (inner) => GzipHttpClient(inner: inner),
      (inner) => RateLimitedHttpClient(
        inner: inner,
        tokensPerSecond: 10,
        burst: 20,
      ),
    ],
  ),
);
```

Wrappers are listed from outermost to innermost. The generated pipeline in
this example is
`HmacSigned(Retrying(CircuitBreaker(EtagCache(Gzip(RateLimited(transport))))))`.

The configuration accepts any existing or future `HttpClient` wrapper. This
keeps OAuth2 token stores, HMAC secrets, cache lifetimes, compression policy,
retry policy, and circuit-breaker state in application code instead of placing
runtime credentials or policy objects inside a const annotation.

## Compatibility

- `createApiClient()` remains valid and continues resolving `dRest.client`.
- The `@RestClient` annotation is unchanged.
- Generated files are still produced by `build_runner`; none are edited by
  hand.
- The wrapper composition is per generated-client instance.

## Changelog note for 2.1.0

Add a REST codegen entry describing per-client HTTP pipeline injection through
`RestClientConfig`, preserving the global fallback while enabling composition
of retry, circuit-breaker, rate-limit, OAuth2, cache, compression, HMAC, and
future `HttpClient` wrappers.
