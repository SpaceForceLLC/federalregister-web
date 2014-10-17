C{
  #include <stdlib.h>
  #include <stdio.h>
  #include <time.h>
}C

backend fr2 {
  .host = "127.0.0.1";
  .port = "3000";
}

backend my_fr2 {
  .host = "127.0.0.1";
  .port = "3001";
}

backend assets_my_fr2 {
  .host = "127.0.0.1";
  .port = "3001";
}

backend blog {
  .host = "127.0.0.1";
  .port = "8000";
}


sub vcl_fetch {
  if (req.url ~ "^(/blog|/policy|/learn|/layout/footer_page_list|/layout/navigation_page_list|/layout/homepage_post_list)") {
   set beresp.ttl = 120s;
  }
}

sub vcl_recv {
    # Reject Non-RFC2616 or CONNECT or TRACE requests.
    if (req.request != "GET" &&
      req.request != "HEAD" &&
      req.request != "PUT" &&
      req.request != "POST" &&
      req.request != "OPTIONS" &&
      req.request != "DELETE") {
        return (error);
    }

    if (req.http.Cookie ~ "(^|;) ?ab_group=\d+(;|$)") {
      if( req.http.Cookie ~ "ab_group=[0-9]+" ) {
        set req.http.X-AB-Group = regsub( req.http.Cookie,    ".*ab_group=", "");
        set req.http.X-AB-Group = regsub( req.http.X-AB-Group, ";.*", "");
      }
    } else {
      C{
        char buff[5];
        sprintf(buff,"%d",rand()%10 != 0 ? 1 : 2);
        VRT_SetHdr(sp, HDR_REQ, "\013X-AB-Group:", buff, vrt_magic_string_end);
      }C

      set req.http.X-Added-AB-Group = "1";

      if (req.http.Cookie) {
        set req.http.Cookie = req.http.Cookie ";";
      } else {
        set req.http.Cookie = "";
      }
      set req.http.Cookie = req.http.Cookie "ab_group=" req.http.X-AB-Group;
    }

    # Rewrite api. subdomain to api/ subdirectory
    if (req.http.host ~ "^api.") {
      if (req.url !~ "^/api/") {
        set req.url = "/api" req.url;
      }
    }

    # Add a unique header containing the client address
    remove req.http.X-Forwarded-For;
    set    req.http.X-Forwarded-For = client.ip;

    # Route to the correct backend
    if (req.url ~ "^/assets/") {
      set req.backend = assets_my_fr2;
      return(pass);
    } else if (req.url ~ "^/my(/|$)") {
      set req.backend = my_fr2;
      return(pass);
    } else if (req.url ~ "^/styleguides(/|$)") {
      set req.backend = my_fr2;
      return(pass);
    } else if (req.url ~ "^(/special/header|/special/shared_assets|/special/my_fr_assets|/special/user_utils)") {
      set req.backend = my_fr2;
      return(pass);
    } else if (req.url ~ "^/api/") {
      set req.backend = fr2;
      return (lookup);
    } else if (req.url ~ "^(/documents/html/)") {
      set req.backend = fr2;
      return (pass);
    } else if (req.url ~ "^(/documents|/d/|/a/)") {
      set req.backend = my_fr2;
      return (pass);
    } else if (req.url ~ "^(/public-inspection|/reader-aids)") {
      set req.backend = my_fr2;
      return (pass);
    } else if (req.url ~ "^(/esi)") {
      set req.backend = my_fr2;
      return (pass);
    } else if (req.url ~ "^(/blog|/policy|/learn|/layout/footer_page_list|/layout/navigation_page_list|/layout/homepage_post_list)") {
      set req.http.host = "127.0.0.1";
      set req.backend = blog;

      # Don't cache wordpress pages if logged in to wp
      if (req.http.Cookie ~ "wordpress_logged_in_") {
          return (pass);
      }
    } else if (req.url == "/") {
      set req.backend = my_fr2;
      return(pass);
    } else {
      set req.http.host = "127.0.0.1";
      set req.backend = fr2;
    }

    # Pass POSTs etc directly on to the backend
    if (req.request != "GET" && req.request != "HEAD") {
        return (pass);
    }

    # Pass fr2 admin requests directly on to fr2
    if (req.url ~ "^/admin" ){
        set req.backend = fr2;
        return (pass);
    }

    # Rewrite top-level wordpress requests to /blog/
    set req.url = regsub(
        req.url,
        "^/(learn|policy|layout/footer_page_list|layout/navigation_page_list|layout/homepage_post_list)",
        "/blog/\1"
    );


    # Pass wp admin requests directly on to wp
    if (req.url ~ "^(/wp-login|wp-admin)") {
        set req.backend = blog;
        set req.http.host = "fr2.local";
        return (pass);
    }

    # either return lookup for caching or return pass for no caching
    
      # Fetch from cache unless explicitly skipping cache
      if (req.http.Cookie ~ "skip_cache=012345678901234567890123456789") {
        return (pass);
      } else {
        return (lookup);
      }
    
}

sub vcl_fetch {
    

    # Directly serve static content
    if (req.url ~ "^(/images|/javascripts|/flash|/stylesheets|/sitemap)") {
        return(deliver);
    }
    # ESI process the rest
    else {
        esi;
    }
}

# vcl_hash creates the key for varnish under which the object is stored. It is
# possible to store the same url under 2 different keys, by making vcl_hash
# create a different hash.
sub vcl_hash {

    # these 2 entries are the default ones used for vcl. Below we add our own.
    set req.hash += req.url;
    set req.hash += req.http.host;

    if (req.url ~ "^/layout/head_content" ) {
      set req.hash += "ab_group";
      set req.hash += req.http.X-AB-Group;
    }

    # Hash differently based on presence of javascript_enabled cookie.
    if( req.url ~ "^/articles/search/header" && req.http.Cookie ~ "javascript_enabled=1" ) {
        # add this fact to the hash
        set req.hash += "javascript enabled";
    }

    return(hash);
}

sub vcl_error {
    set obj.http.Content-Type = "text/html; charset=utf-8";

    synthetic {"<!--"} obj.status " " obj.response {"-->"};
    return(deliver);
}

sub vcl_deliver {
    
        set resp.http.Etag = resp.http.Etag " abgroup=" req.http.X-AB-Group;
    

    if (req.http.X-Added-AB-Group) {
        # set resp.http.Set-Cookie = "ab_group=" req.http.X-AB-Group "; path=/";
        C{
          time_t now;
          time(&now);
          now = now + 10*24*60*60;

          char expires [30];
          strftime( expires, 30, "%a, %d-%b-%Y %H:%M:%S GMT", localtime(&now));

          VRT_count(sp, 57);
          VRT_SetHdr(sp, HDR_RESP, "\013Set-Cookie:", "ab_group=", VRT_GetHdr(sp, HDR_REQ, "\013X-AB-Group:"), "; path=/; expires=", expires, vrt_magic_string_end);
        }C
    }
}

