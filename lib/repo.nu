export def clone [url: string, ref: string]: nothing -> path {
  let parts = ($url | parse -r '^https://(?<provider>[^/]+)/(?<owner>[^/]+)/(?<repo>[^/.]+)' | get -o 0)
  if ($parts | is-empty) { error make {msg: $"cannot parse repo url: ($url)"} }

  let dir = ([$nu.home-dir "code" $parts.provider $parts.owner $parts.repo] | path join)

  if ($dir | path exists) {
    ^git -C $dir fetch --tags --quiet
  } else {
    mkdir ($dir | path dirname)
    ^git clone --quiet $url $dir
  }
  ^git -C $dir checkout --quiet $ref
  $dir
}


