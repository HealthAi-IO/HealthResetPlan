# Content interaction API

All endpoints require an authenticated user and return the existing envelope:

```json
{ "code": 0, "message": "ok", "data": {} }
```

## Read interaction state

`GET /api/v1/content/{contentId}/interactions`

## Set or clear reaction

`PUT /api/v1/content/{contentId}/reaction`

```json
{ "reaction": "like" }
```

`reaction` accepts `like`, `dislike`, or an empty string. A user has at most
one reaction for each article.

## Add comment

`POST /api/v1/content/{contentId}/comments`

```json
{ "content": "评论正文，最多 500 字" }
```

## Delete own comment

`DELETE /api/v1/content/{contentId}/comments/{commentId}`

The four endpoints return the complete current interaction state:

```json
{
  "likeCount": 12,
  "dislikeCount": 1,
  "userReaction": "like",
  "comments": [
    {
      "id": 8,
      "authorName": "小柳",
      "content": "这篇内容很实用。",
      "createdAt": "2026-08-10T12:30:00+08:00",
      "isMine": true
    }
  ]
}
```

The server must sanitize comment text, enforce the 500-character limit,
allow users to delete only their own comments, and apply the product's content
moderation rules before publishing a comment.
