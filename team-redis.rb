#require 'rubygems'
require 'sinatra'
require 'redis'
require 'haml'

enable :inline_templates

DB      = Redis.new()
DB.select 3
if not DB.sismember "users", "rich" or not DB.sismember "users", "eric"
  DB.sadd "users", "rich"
  DB.sadd "admin", "rich"
  DB.sadd "users", "eric"
  DB.sadd "admin", "eric"
  DB.hset "user:rich", "pwmd5", "6ae199a93c381bf6d5de27491139d3f9"
  DB.hset "user:eric", "pwmd5", "5d1d88238cb3222b1798127b285b827c"
end
AREAS   = [["My Items","myitems"],["Team Priorities","priority"],["Projects","project"],["Team Tasks","task"],["Prospects","prospect"]]
UNPROTECTED_PAGES = ["/","/login"]
before do
  unless UNPROTECTED_PAGES.include?(request.path_info)
    @user = request.cookies["ttb_team_tracker_logged_in"]
    redirect('/') if @user.nil?
  end
end
after do
  if not @user.nil?
    DB.hset "user:rich", "lastactivity_at", Time.now
    #USERS.update({"user" => @user},{"$set" => {"last_activity" => Time.now}})
  end
end
get '/' do
  haml :root
end
get '/archive' do
  @items = DB.smembers "archive_ids"
  haml :archive
end
get '/archivedelete/:id' do
  ITEMS.remove({"_id" => Mongo::ObjectID.from_string(params[:id]), "archived" => true}, {:safe => true})
  logme("deleted archived item #{params[:id]}")
  redirect('/archive')
end 
get '/archiveitem/:id' do
  @users = USERS.find({},{:sort => [:user,'ascending']}).to_a
  @archive = true
  @item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id]), "archived" => true})
  @tasks = @item["tasks"] ? @item["tasks"].sort {|x,y| x["order"] <=> y["order"]} : []
  haml :item
end
get '/archiverestore/:id' do
  DB.smove "archive_ids", "#{DB.HGET "item:#{params[:id]}", "type"}_ids", params[:id]
  logme("unarchived item #{params[:id]}")
  redirect('/archive')
end
get '/item/:id' do
  @item = DB.hgetall "item:#{params[:id]}"
  #@item  = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  #@tasks = @item["tasks"] ? @item["tasks"].sort {|x,y| x["order"] <=> y["order"]} : []
  @users = DB.smembers "users"
  haml :item
end
post '/itemmessageadd/:id' do
  DB.LPUSH "messages:#{params[:id]}", "#{@user.capitalize} said: #{params[:text]} <i>at #{Time.now.strftime("%Y-%m-%d %I:%M:%S%p")}</i>"
  logme("added a message to item #{params[:id]}")
  redirect("/item/#{params[:id]}")
end
get '/itemmessagedelete/:id/:index' do
  DB.LREM "messages:#{params[:id]}", 1, (DB.LRANGE "messages:#{params[:id]}", params[:index], params[:index])[0]
  #item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  #ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])},{"$pull" => {"messages" => {"text" => item["messages"][params[:index].to_i]["text"],"date" => item["messages"][params[:index].to_i]["date"]}}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}})
  logme("deleted message on item #{params[:id]}")
  redirect back
end
post '/itemtaskadd/:id' do
  DB.ZADD "tasks:#{params[:id]}",(DB.ZCARD "tasks:#{params[:id]}")*10, params[:text]
  logme("added a task to item #{params[:id]}")
  redirect("/item/#{params[:id]}")
end
get '/itemtaskdelete/:id/:index' do
  item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])},{"$pull" => {"tasks" => {"text" => item["tasks"][params[:index].to_i]["text"],"date" => item["tasks"][params[:index].to_i]["date"]}}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}})
  logme("deleted task on item #{params[:id]}")
  redirect back
end
get '/itemtaskdown/:id/:index' do
  items = DB.ZRANGE "tasks:#{params[:id]}", params[:index].to_i, params[:index].to_i+1
  score0 = DB.ZSCORE "tasks:#{params[:id]}", items[0]
  score1 = DB.ZSCORE "tasks:#{params[:id]}", items[1]
  DB.ZADD "tasks:#{params[:id]}", score1, items[0]
  DB.ZADD "tasks:#{params[:id]}", score0, items[1]
  logme("moved down task item #{params[:id]}")
  redirect back
end
post '/itemtasktoggle/:id/:index' do
  item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  item["tasks"].each_with_index do |t,i|
    ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])},{"$set" => {"tasks.#{i}.complete" => (item["tasks"][i]["complete"] ? false : true), "updated_at" => Time.now,"updated_by" => @user}}) if t["order"] == params[:index].to_i
  end
  logme("toggled task on item #{params[:id]}")
  redirect back
end
get '/itemtaskup/:id/:index' do
  items = DB.ZRANGE "tasks:#{params[:id]}", params[:index].to_i-1, params[:index].to_i
  score0 = DB.ZSCORE "tasks:#{params[:id]}", items[0]
  score1 = DB.ZSCORE "tasks:#{params[:id]}", items[1]
  DB.ZADD "tasks:#{params[:id]}", score1, items[0]
  DB.ZADD "tasks:#{params[:id]}", score0, items[1]
  logme("moved down task item #{params[:id]}")
  redirect back
end
get '/items' do 
  @priorities   = DB.smembers "priority_ids"
  @projects     = DB.smembers "project_ids"
  @prospects    = DB.smembers "prospect_ids"
  @tasks        = DB.smembers "task_ids"
  @random       = DB.get "random"
  @myitems      = DB.smembers "user:#{@user}:item_ids"
  @archives     = DB.scard "archive_ids"
  haml :items
end
get '/itemarchive/:id' do
  if DB.sismember "priority_ids", params[:id]
    DB.smove "priority_ids", "archive_ids", params[:id]
    DB.hset "item:#{params[:id]}", "type", "priority"
  elsif DB.sismember "prospect_ids", params[:id]
    DB.smove "prospect_ids", "archive_ids", params[:id]
    DB.hset "item:#{params[:id]}", "type", "prospect"
  elsif DB.sismember "task_ids", params[:id]
    DB.smove "task_ids", "archive_ids", params[:id]
    DB.hset "item:#{params[:id]}", "type", "task"
  elsif DB.sismember "project_ids", params[:id]
    DB.smove "project_ids", "archive_ids", params[:id]
    DB.hset "item:#{params[:id]}", "type", "project"
  end
  #ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])}, {"$set" => {"archived" => true, "updated_at" => Time.now, "updated_by" => @user}})
  logme("archived item #{params[:id]}")
  redirect('/items')
end 
get '/itemdown/:id' do
  item1 = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  if ITEMS.find({"type" => item1["type"], "order" => {"$gt" => item1["order"]}}).count > 0
    ITEMS.update({"type" => item1["type"],"order" => item1["order"]+1},{"$inc" => {"order" => -1}})
    ITEMS.update({"_id" => item1["_id"]},{"$inc" => {"order" => 1}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}})
    logme("moved down item #{params[:id]}")
  end
  redirect('/items')
end
post '/itemnew/:type' do
  if params[:item].size > 0
    #count = ITEMS.find({"type" => params[:type]}).count
    assigned_user = ""
    assigned_user, params[:item] = params[:item].split(" ",2) if params[:item][0] == "@"
    assigned_user = assigned_user[1..-1]
    id = Digest::MD5.hexdigest(params[:item]+Time.now.to_s)
    DB.hset "item:#{id}", "text", params[:item]
    DB.hset "item:#{id}", "user", assigned_user
    DB.hset "item:#{id}", "idx", (DB.scard "#{params[:type]}_ids")
    DB.sadd "#{params[:type]}_ids", id
    DB.sadd "user:#{assigned_user}:item_ids", id
    #logme("added item #{id}")
  end
  redirect('/items')
end
get '/itemtoproject/:id' do
  DB.SMOVE "task_ids","project_ids", params[:id] if DB.SISMEMBER "task_ids", params[:id]
  DB.SMOVE "prospect_ids","project_ids", params[:id] if DB.SISMEMBER "prospect_ids", params[:id]
  redirect("/item/#{params[:id]}")
end
get '/itemtoprospect/:id' do
  DB.SMOVE "task_ids","prospect_ids", params[:id] if DB.SISMEMBER "task_ids", params[:id]
  DB.SMOVE "project_ids","prospect_ids", params[:id] if DB.SISMEMBER "project_ids", params[:id]
  redirect back
end
get '/itemtotask/:id' do
  DB.SMOVE "project_ids","task_ids", params[:id] if DB.SISMEMBER "project_ids", params[:id]
  DB.SMOVE "prospect_ids","task_ids", params[:id] if DB.SISMEMBER "prospect_ids", params[:id]
  redirect back
end
get '/itemup/:id' do
  item1 = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  if item1["order"] >= 1
    ITEMS.update({"type" => item1["type"],"order" => item1["order"]-1},{"$inc" => {"order" => 1}})
    ITEMS.update({"_id" => item1["_id"]},{"$inc" => {"order" => -1}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}})
    logme("moved up item #{params[:id]}")
  end
  redirect('/items')
end
post '/itemupdate/:id' do
  DB.hset "item:#{params[:id]}", "text", params[:text]
  DB.hset "item:#{params[:id]}", "blob", params[:blob]
  DB.hset "item:#{params[:id]}", "user", params[:assigned_user].downcase
  DB.hset "item:#{params[:id]}", "updated_at", Time.now
  (DB.smembers "users").each do |u|
    DB.srem "user:#{u}:items", params[:id]
  end
  DB.sadd "user:#{params[:assigned_user].downcase}:item_ids", params[:id]
  #ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])},{"$set" => {"text" => params[:text], "assigned_user" => params[:assigned_user].downcase, "blob" => params[:blob], "updated_at" => Time.now,"updated_by" => @user}})
  logme("updated item #{params[:id]}")
  redirect("/item/#{params[:id]}")
end
get '/itemuserhourdec/:id/:user' do
  item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  if item["hours"].nil?
    USERS.find({},{:sort => [:user,1]}).each do |u|
      ITEMS.update({"_id" => item["_id"]},{"$push" => {"hours" => {"by" => u["user"], "byhours" => 0}}})
    end
  end
  if item["totalhours"].nil?
    ITEMS.update({"_id" => item["_id"]},{"$set" => {"totalhours" => 0}})
  end
  #puts item["hours"].inspect
  ITEMS.update({"_id" => item["_id"],"hours.byhours" => {"$gt" => 0}, "hours.by" => params[:user]},{"$inc" => {"hours.$.byhours" => -1}})
  ITEMS.update({"_id" => item["_id"],"totalhours" => {"$gt" => 0}},{"$inc" => {"totalhours" => -1}})
  redirect back
end
get '/itemuserhourinc/:id/:user' do
  item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  if item["hours"].nil?
    USERS.find({},{:sort => [:user,1]}).each do |u|
      ITEMS.update({"_id" => item["_id"]},{"$push" => {"hours" => {"by" => u["user"], "byhours" => 0}}})
    end
  end
  ITEMS.update({"_id" => item["_id"],"hours.by" => params[:user]},{"$inc" => {"hours.$.byhours" => 1}})
  ITEMS.update({"_id" => item["_id"]},{"$inc" => {"totalhours" => 1}})
  redirect back
end
get '/log' do
  @activities = LOG.find({},{:sort => ["when",-1], :limit => 50})
  haml :log
end
post '/login' do
  require 'digest/md5'
  @pwmd5 = DB.hget "user:#{params[:user]}", "pwmd5" #USERS.find_one({"user" => params[:user].downcase, "pwdmd5" => Digest::MD5.hexdigest(params[:pass])})
  if @pwmd5 == Digest::MD5.hexdigest(params[:pass])
    response.set_cookie("ttb_team_tracker_logged_in", params[:user].downcase)
    DB.hset "user:rich", "lastlogin_at", Time.now
    #logme("#{params[:user].downcase} logged in")
    redirect('/items')
  else
    redirect('/')
  end
end
get '/logout' do
  response.set_cookie("ttb_team_tracker_logged_in", nil)
  logme("logged out")
  redirect('/')
end
get '/password' do
  haml :password
end
post '/password' do
  require 'digest/md5'
  user = USERS.find_one({"user" => @user})
  if Digest::MD5.hexdigest(params[:original]) == user["pwdmd5"] and params[:password] == params[:confirm]
    USERS.update({"_id" => user["_id"]}, {"$set" => {"pwdmd5" => Digest::MD5.hexdigest(params[:password])}})
    redirect('/items')
  else
    redirect('/password')
  end
end
get '/statuses' do
  @users = USERS.find({},{:sort => [:user,1]})
  haml :statuses
end
post '/statusupdate' do
  USERS.update({"user" => @user},{"$set" => {"status" => params[:status], "status_date" => Time.now}})
  redirect back
end
post '/update/:item' do
  if params[:item] == "random"
    DB.set "random", params[:text]
  end
  #ITEMS.update({"type" => params[:item]}, {"$set" => {"text" => params[:text], "updated_at" => Time.now,"updated_by" => @user}})
  logme("updated #{params[:item]}")
  redirect('/items')
end

helpers do

  def chatmessage(m)
    tmp =  "<div class='chatleft'>#{m["author"]}: </div>"
    tmp += "<div class='chatright'>#{m["text"]} <i>(#{m["created_at"].localtime.strftime("%I:%M:%S %p")})</i></div>"
    tmp += "<div class='clear'></div>"
    tmp
  end
  def list(titles)
    data = (titles[1]=="priority" ? @priorities : (titles[1]=="task" ? @tasks : (titles[1]=="project" ? @projects : (titles[1]=="prospect" ? @prospects : @myitems))))
    html = "<h3>#{titles[0]}</h3>"
    html += "<form action='/itemnew/#{titles[1]}' method='post' ><input type='text' name='item' size='60' /><input type='submit' value='Add Item' /></form>" if titles[1] != "myitems"
    html += "<br />" if titles[1] == "myitems" and data.count > 0
    html += "<ul class='items'>"
    #html += data.inspect
    keys = []
    data.each do |i|
      text = DB.hget "item:#{i}", "text"
      user = DB.hget "item:#{i}", "user"
      html += "<li><a href='/item/#{i}'>#{text} (#{(user.nil? or user=="") ? "no user" : user})</a> <a href='/itemarchive/#{i}'>X</a>"
    end
    html += "</ul>"
    html += "&nbsp;&nbsp;No items." if data.count == 0
    html
  end
  def logme(what)
  end
  def reject_blank(url)
    redirect('/') unless url.size > 0
  end
  def send_data(data, options = {}) #:doc:
    send_file_headers! options.merge(:length => data.size)
    throw :halt, [options[:status] || 200, [data]]
  end

end

__END__

@@ layout
%html
  %head
    %title Team Tracker
    %style{:type => "text/css", :media => "screen"}
      :plain
        a.nounderline  { text-decoration:none; }
        body           { font-family:Verdana;font-size:0.8em;padding:10px; }
        h3             { margin:0;padding:5; }
        html           { background-color: #FFFFFF; /* fallback color */
                         background-image: -moz-linear-gradient(100% 100% 90deg, #DDE5F0, #FFFFFF);
                         background-image: -webkit-gradient(linear, 0 0, 0 100%, from(#DDE5F0), to(#FFFFFF)); } 
        pre            { white-space: pre-wrap; white-space: -moz-pre-wrap; white-space: -pre-wrap; white-space: -o-pre-wrap; word-wrap: break-word; }
        ul             { margin-top:-10px;padding-left:40px; }
        ul.items       { list-style:decimal-leading-zero;margin-top:-10px;padding-left:40px; }
        #chat          { background-color:#FFFFFF;border:1px solid #B0C3DB;height:400px;overflow:auto;padding:5px; }
        #leftcolumn    { float:left;width:550px; }
        #rightcolumn   { float:left;width:550px; }
        #roster        { color:#AAA;font-size:0.8em;font-style:italic; }
        #wrapper       { margin:0 auto;width:1100px; }
        .chatleft      { float:left;width:80px; }
        .chatright     { float:left;width:420px; }
        .clear         { clear:both; }
        .dashleft      { float:left;margin-left:10px;width:110px;}
        .dashmiddle    { float:left;width:75px;}
        .dashproject   { background-color:plum;float:left;padding-right:3px;text-align:right;width:65px; }
        .dashprospect  { background-color:pink;float:left;padding-right:3px;text-align:right;width:65px; }
        .dashpriority  { background-color:lightgreen;float:left;padding-right:3px;text-align:right;width:65px; }
        .dashtask      { background-color:lightyellow;float:left;padding-right:3px;text-align:right;width:65px; }
        .dashright     { float:left;width:350px; }
        .message       { padding:3px; }
        .messageleft   { float:left;text-align:right;width:95px; }
        .messageright  { float:left;width:445px; }
        .meta          { font-size:0.8em;font-style:italic; }
        .taskleft      { float:left;text-align:right;width:25px; }
        .taskright     { float:left;width:500px; }
        .textright     { text-align:right; }

  %body
    #wrapper
      = yield

@@ archive
%h2 Archive
%a{ :href => "/items" }= "Back to Home"
- @items.each do |i|
  %p
    = "<a href='/archiveitem/#{i}'>#{DB.hget "item:#{i}", "text"}</a>"
    = "<a class='nounderline' href='/archivedelete/#{i}'>&#215;</a>"
    = "<a class='nounderline' href='/archiverestore/#{i}'>&larr;</a>"

@@ chat
%h3 Chat
#chat
  - @chats.each do |c|
    =chatmessage(c)
#roster= "&nbsp;Who's here: #{@roster}"
%form{ :id => "chatform" }
  %input{ :type => "text", :name => "chattext", :id => "chattext", :size => "90" }
  %input{ :type => "submit", :value => "Send", :id => "chat_btn" }
%script{ :src => "http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js" }
:javascript 
  $(document).ready(function() {
    document.getElementById("chat").scrollTop = document.getElementById("chat").scrollHeight;
    //chatupdate is called every 5 seconds to get new messages
    var updates = setInterval(function() { $.get('chatupdate', function(data) { $('#chat').append(data.split('>>>>>')[1]);document.getElementById('roster').innerHTML='&nbsp;Who\'s here: '+data.split('>>>>>')[0];document.getElementById("chat").scrollTop=document.getElementById("chat").scrollHeight;} ); }, 5000);
  });
  $("form#chatform").submit(function() {$.post("/chatmessagenew", $("#chatform").serialize());document.getElementById("chattext").value='';return false;});
  function scrollDown () { var objDiv = document.getElementById("chat"); objDiv.scrollTop = objDiv.scrollHeight; }

@@ item
- title = ''
- if DB.sismember "task_ids", params[:id]
  - title = "TASK: "
  - elsif DB.sismember "project_ids", params[:id]
    - title = "PROJECT: "
    - elsif DB.sismember "prospect_ids", params[:id]
      - title = "PROSPECT: "
%h2= "#{title} #{@item["text"]}"
//%p= "<i>Last modified by #{@item["updated_by"].capitalize} on #{@item["updated_at"].localtime.strftime("%Y-%m-%d at %I:%M %p")}.</i>"
#leftcolumn
  - if @archive
    %a{ :href => "/archive" }= "Back to Archive"
    |
    %a{ :href => "/itemtoproject/#{params[:id]}" }= "Convert to Project"
    | 
    %a{ :href => "/items" }= "Back to Home"
  - else
    %a{ :href => "/items" }= "Back to Home"
    - if not DB.sismember "task_ids", params[:id]
      |
      %a{ :href => "/itemtotask/#{params[:id]}" }= "Convert to Task"
    - if not DB.sismember "project_ids", params[:id]
      |
      %a{ :href => "/itemtoproject/#{params[:id]}" }= "Convert to Project"
    - if not DB.sismember "prospect_ids", params[:id]
      |
      %a{ :href => "/itemtoprospect/#{params[:id]}" }= "Convert to Prospect"
    |
    %a{ :href => "/itemarchive/#{params[:id]}" }= "Archive"
  %br
  %br
  %form{ :action => "/itemupdate/#{params[:id]}", :method => "post" }
    - if @archive
      %input{ :type => "text", :name => "text", :size => "70", :value => @item["text"], :readonly => "readonly" }
      %br
      %textarea{ :name => "blob", :cols => "70", :rows => "10", :readonly => "yes" }= @item["blob"]
    - else
      %input{ :type => "text", :name => "text", :size => "70", :value => @item["text"] }
      %br
      %textarea{ :name => "blob", :cols => "70", :rows => "10" }= @item["blob"]
      %br
      = "Assigned to: "
      %select{ :name => "assigned_user" }
        %option{ :selected => @item["user"].nil? }= ""
        - @users.each do |u|
          %option{ :selected => @item["user"]==u }= u.capitalize
    %br
    - if not @archive
      %input{ :type => "submit", :value => "Update Item" }
  %h3 Hours
  - (DB.smembers "users").each do |u|
    = "[#{u.capitalize} (#{DB.hget "item:#{params[:id]}", "hours:#{u}"}) <a href='/itemuserhourinc/#{params[:id]}/#{u}' style='text-decoration:none;'> + </a> <a href='/itemuserhourdec/#{params[:id]}/#{u}' style='text-decoration:none;'> - </a>]"
  %h3 Tasks
  - if not @archive
    %form{ :action => "/itemtaskadd/#{params[:id]}", :method => "post" }
      %input{ :type => "text", :name => "text", :size => "60" }
      %input{ :type => "submit", :value => "Add Task" }
  - (DB.zrange "tasks:#{params[:id]}",0,-1).each_with_index do |t,i|
    .taskleft
      %form
        - if not @archive
          %input{ :type => "checkbox", :style => "font-size:0.3em;", :checked => t["complete"], :onClick => (@archive ? "" : "this.form.action='/itemtasktoggle/#{params[:id]}/#{i}'; this.form.method='POST'; this.form.submit(); return false;") }
    .taskright
      - if @archive
        = " - "
      = "#{t}"
      - if not @archive
        = "<a class='nounderline' href='/itemtaskdelete/#{params[:id]}/#{i}'>&#215;</a> #{i>0 ? "<a class='nounderline' href='/itemtaskup/#{params[:id]}/#{i}'>&uarr;</a>" : ""} #{i<(DB.zcard "tasks:#{params[:id]}")-1 ? "<a class='nounderline' href='/itemtaskdown/#{params[:id]}/#{i}'>&darr;</a>" : ""}"
    .clear
  %br
#rightcolumn
  %h3 Messages
  - if @item["archived"].nil?
    %form{ :action => "/itemmessageadd/#{params[:id]}", :method => "post" }
      %textarea{ :name => "text", :cols => 70, :rows => 5 }
      %br
      %input{ :type => "submit", :value => "Add Message" }
  - (DB.lrange "messages:#{params[:id]}", 0, -1).each_with_index do |m,i|
    %div.message{ :style => "background-color: #{i % 2 == 0 ? "white" : ""};" }
      .messageright
        %pre{:style => "font-family:Verdana;margin-top:0px;margin-bottom:0px;padding-bottom:0px;padding-top:0px;"}= "#{m} <a class='nounderline' href='/itemmessagedelete/#{params[:id]}/#{i}'>&#215;</a>"
      .clear
  %br

@@ items
#leftcolumn
  %h3= "TEAM TRACKER : <a href='/archive'>Archive (#{@archives})</a> | <a href='/log'>Activity Log</a> | <a href='/statuses'>Statuses</a>"
  = list(AREAS[0])  # My Items
  = list(AREAS[2])  # Projects
  = list(AREAS[4])  # Prospects
  %h3 Random
  %form{ :action => "/update/random", :method => "post" }
    %textarea{ :name => "text", :cols => "70", :rows => "7" }= @random
    %br
    %input{ :type => "submit", :value => "Update" }
#rightcolumn
  %h3.textright= "Welcome, \"#{@user.capitalize}\" : <a href='/password'>Change Password</a> | <a href='/logout'>Logout</a>"
  = list(AREAS[1])
  = list(AREAS[3])  # Tasks
  
@@ log
%h2 Log
- @activities.each do |a|
  %p= "On #{a["when"].localtime.strftime("%Y%m%d")} at #{a["when"].localtime.strftime("%H:%M:%S %p")} #{a["who"] ? a["who"] : "none"} #{a["what"]}"

@@ password
%form{ :action => "/password", :method => "post" }
  %table
    %tr
      %td.textright= "Original Password:"
      %td
        %input{ :type => "password", :name => "original" }
    %tr
      %td.textright= "New Password:"
      %td
        %input{ :type => "password", :name => "password" }
    %tr
      %td.textright= "Confirm New Password:"
      %td
        %input{ :type => "password", :name => "confirm" }
    %tr
      %td= " "
      %td
        %input{ :type => "submit", :value => "Change Password" }

@@ root
%form{ :action => "/login", :method => "post" }
  #leftcolumn.textright= "User:<br />Password:"
  #rightcolumn
    %input{ :type => "text", :name => "user" }
    %br
    %input{ :type => "password", :name => "pass" }
    %br
    %input{ :type => "submit", :value => "login" }

@@ statuses
%h3 Statuses
%form{ :action => "/statusupdate", :method => "post" }
  %input{ :type => "text", :name => "status", :size => "90" }
  %input{ :type => "submit", :value => "Update My Status" }
- @users.each do |u|
  .messageleft= "<b>#{u["user"]}:&nbsp;</b>"
  .messageright= "#{u["status"].nil? ? "none" : u["status"]}<br /><i>(as of #{u["status_date"].nil? ? "never" : u["status_date"]}, last activity on #{u["last_activity"].nil? ? "never" : u["last_activity"].localtime.strftime("%Y-%m-%d")})</i>"
  .clear
%br
%a{ :href => "/items" }= "Back to Home"

