#ifndef HN_UTILS_JSON_UTIL
#define HN_UTILS_JSON_UTIL

/* Thin accessors over the holyc-lang stdlib Json tree (json.HC).
 * Returned pointers are borrowed from the parsed document - never freed here. */

Json *JField(Json *obj, U8 *key)
{
  if (!obj || !key) return NULL;
  if (obj->type != JSON_OBJECT) return NULL;
  Json *el = obj->object;
  while (el != NULL) {
    if (el->key != NULL && StrCmp(el->key, key) == 0) return el;
    el = el->next;
  }
  return NULL;
}

/* Dotted lookup, e.g. JPath(root, "output.directory"). */
Json *JPath(Json *obj, U8 *path)
{
  if (!obj || !path) return NULL;
  Json *cur = obj;
  U8 *p = StrDup(path);
  I64 start = 0, i = 0;
  while (TRUE) {
    if (p[i] == '.' || p[i] == 0) {
      Bool last = p[i] == 0;
      p[i] = 0;
      cur = JField(cur, p + start);
      if (!cur) break;
      if (last) break;
      start = i + 1;
    }
    i++;
  }
  Free(p);
  return cur;
}

U8 *JStr(Json *obj, U8 *key, U8 *fallback)
{
  Json *f = JField(obj, key);
  if (!f) return fallback;
  if (f->type == JSON_STRING) return f->str;
  if (f->type == JSON_STRNUM) return f->strnum;
  return fallback;
}

I64 JInt(Json *obj, U8 *key, I64 fallback)
{
  Json *f = JField(obj, key);
  if (!f) return fallback;
  if (f->type == JSON_INT) return f->i64;
  if (f->type == JSON_FLOAT) return f->f64;
  if (f->type == JSON_STRNUM) return Atoi(f->strnum);
  if (f->type == JSON_STRING) return Atoi(f->str);
  return fallback;
}

Bool JBool(Json *obj, U8 *key, Bool fallback)
{
  Json *f = JField(obj, key);
  if (!f) return fallback;
  if (f->type == JSON_BOOL) return f->boolean;
  if (f->type == JSON_INT) return f->i64 != 0;
  return fallback;
}

Json *JObjField(Json *obj, U8 *key)
{
  Json *f = JField(obj, key);
  if (f && f->type == JSON_OBJECT) return f;
  return NULL;
}

Json *JArrField(Json *obj, U8 *key)
{
  Json *f = JField(obj, key);
  if (f && f->type == JSON_ARRAY) return f;
  return NULL;
}

/* First element of an array node; iterate with ->next. */
Json *JArrFirst(Json *arr)
{
  if (!arr || arr->type != JSON_ARRAY) return NULL;
  return arr->array;
}

/* A string value directly off a node (not a keyed lookup). */
U8 *JAsStr(Json *node, U8 *fallback)
{
  if (!node) return fallback;
  if (node->type == JSON_STRING) return node->str;
  if (node->type == JSON_STRNUM) return node->strnum;
  return fallback;
}

/* Re-emits a JSON-RPC id exactly as received. Only string and number ids are
 * legal in JSON-RPC 2.0; anything else degrades to null. */
U0 SbCatRpcId(StrBuf *sb, Json *id)
{
  if (!id) { SbCat(sb, "null"); return; }
  switch (id->type) {
    case JSON_STRING: SbCatJson(sb, id->str);    break;
    case JSON_INT:    SbCatI64(sb, id->i64);     break;
    case JSON_STRNUM: SbCat(sb, id->strnum);     break;
    default:          SbCat(sb, "null");         break;
  }
}

#endif
