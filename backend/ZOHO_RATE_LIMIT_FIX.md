# Zoho API Rate Limit Fix

## Issue Summary

**Problem**: The application was hitting Zoho's API rate limit (100 requests per 2 minutes) when fetching portals data.

**Error Message**:
```
Cannot execute more than 100 requests per API in 2 minutes. Try again after 25 minutes.
URL_ROLLING_THROTTLES_LIMIT_EXCEEDED
```

## Root Cause

This was a **CODE ISSUE**, not a Zoho issue. The problem was:

1. **No Caching**: The `getPortals()` method was making a fresh API call to Zoho every time it was called
2. **Multiple Calls**: The method was being called from many places:
   - `getProjects()` method (multiple times)
   - Route handlers (`/api/zoho/projects`, `/api/projects`, etc.)
   - Internal service methods
3. **Rate Limit Exceeded**: When multiple requests came in or a single request triggered multiple calls, it quickly exceeded Zoho's rate limit

## Solution Implemented

Added **in-memory caching** to the `getPortals()` method:

### Features:
- **Per-User Cache**: Each user has their own cached portals data
- **TTL (Time-To-Live)**: Cache expires after 10 minutes
- **Stale Cache Fallback**: If API call fails due to rate limiting, returns stale cache (up to 30 minutes old)
- **Force Refresh Option**: Added optional `forceRefresh` parameter to bypass cache when needed
- **Cache Management**: Added `clearPortalsCache()` method to manually clear cache

### Implementation Details:

```typescript
// Cache structure
interface PortalsCacheEntry {
  portals: any[];
  timestamp: number;
}

// Cache TTL: 10 minutes
private readonly PORTALS_CACHE_TTL = 10 * 60 * 1000;

// Cache storage
private portalsCache: Map<number, PortalsCacheEntry> = new Map();
```

### How It Works:

1. **Cache Check**: Before making an API call, checks if cached data exists and is still valid
2. **Cache Hit**: Returns cached data if available and fresh (< 10 minutes old)
3. **Cache Miss**: Makes API call, caches the result, and returns it
4. **Error Handling**: If API call fails (e.g., rate limit), returns stale cache if available (< 30 minutes old)

## Benefits

1. **Reduced API Calls**: Dramatically reduces the number of calls to Zoho API
2. **Rate Limit Prevention**: Prevents hitting Zoho's rate limits
3. **Better Performance**: Faster response times when cache is hit
4. **Resilience**: Falls back to stale cache if API is temporarily unavailable

## Usage

### Normal Usage (with caching):
```typescript
const portals = await zohoService.getPortals(userId);
```

### Force Refresh (bypass cache):
```typescript
const portals = await zohoService.getPortals(userId, true);
```

### Clear Cache:
```typescript
// Clear cache for specific user
zohoService.clearPortalsCache(userId);

// Clear all caches
zohoService.clearPortalsCache();
```

## Testing

After this fix:
- Multiple rapid requests should not hit rate limits
- Portal data should be cached and reused
- API calls should only be made when cache is expired or missing
- Check server logs for cache hit/miss messages

## Future Improvements

Consider adding similar caching for:
- `getProjects()` method
- Other frequently called Zoho API methods
- Consider using Redis for distributed caching in production

