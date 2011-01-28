require 'rubygems'
require 'sinatra'
require 'mongo'
require 'haml'
include Mongo

enable :inline_templates

DB      = Connection.new('localhost').db('team')
ARCHIVE = DB['archive']
AREAS   = [["My Items","myitems"],["Team Priorities","priority"],["Projects","project"],["Team Tasks","task"],["Prospects","prospect"]]
CHATS   = DB['chats']
CHUNKS  = DB['fs.chunks']
FILES   = DB['fs.files']
ITEMS   = DB['items']
LOG     = DB['log']
ROSTER  = DB['roster']
USERS   = DB['users']
GRID    = GridFileSystem.new(DB)
UNPROTECTED_PAGES = ["/","/login"]

before do
  unless UNPROTECTED_PAGES.include?(request.path_info)
    @user = request.cookies["applabs_team_tracker_logged_in"]
    redirect('/') if @user.nil?
  end
end
after do
  if not @user.nil?
    USERS.update({"user" => @user},{"$set" => {"last_activity" => Time.now}})
  end
end
get '/' do
  haml :root
end
get '/archive' do
  @items = ITEMS.find({"archived" => true},{:sort => ["text",1]})
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
  item = ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id]), "archived" => true},{"$unset" => {"archived" => true}})
  #ITEMS.insert(item)
  #ARCHIVE.remove({"_id" => Mongo::ObjectID.from_string(params[:id])}, {:safe => true})
  logme("unarchived item #{params[:id]}")
  redirect('/archive')
end
#get '/chatupdate' do
  #cookie   = request.cookies["last_chat_message"]
  #ROSTER.update({"user" => @user}, {"$set" => {"user" => @user, "last_connection" => Time.new.to_i}}, {:upsert => true})
  #ROSTER.remove({"last_connection" => {"$lt" => Time.new.to_i-60}})
  #roster   = ROSTER.find().to_a.map {|m| m["user"]}.join(",")
  #lastchat = CHATS.find_one({"_id" => Mongo::ObjectID.from_string(cookie)})
  #messages = CHATS.find({"created_at" => {"$gt" => lastchat["created_at"]}},{:sort => [:created_at, 'descending']}).to_a
  #msgstring = ""
  #messages.reverse.each {|c| msgstring += chatmessage(c)} if messages[0]
  #response.set_cookie(["last_chat_message"],messages[0]["_id"]) if messages[0]
  #msgstring = "#{roster}>>>>>#{msgstring}"
  #msgstring
#end
post '/chatmessagenew' do
  if not params[:chattext].nil? and not params[:chattext] == ""
    CHATS.insert({"author" => @user, "text" => params[:chattext], "created_at" => Time.now})
  end
end
get '/filedelete/:id' do
  FILES.remove({"_id" => Mongo::ObjectID.from_string(params[:id])})
  CHUNKS.remove({"files_id" => Mongo::ObjectID.from_string(params[:id])})
  logme("deleted file #{params[:id]}")
  redirect back
end
get '/filedownload/:id' do
  file = FILES.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  logme("downloaded file #{file["filename"]} with id of #{params[:id]}")
  data = GRID.open(file["filename"], "r").read
  content_type file["contentType"]
  attachment file["filename"]
  data
end
post '/fileupload' do
  unless params[:file] && (tmpfile = params[:file][:tempfile]) && (name = params[:file][:filename])
    @error = "No file selected"
    redirect back
  end
  GRID.open(params[:file][:filename], "w") { |f| f.write params[:file][:tempfile] }
  logme("uploaded file #{params[:file][:filename]}")
  redirect back
end
get '/item/:id' do
  @item  = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  @tasks = @item["tasks"] ? @item["tasks"].sort {|x,y| x["order"] <=> y["order"]} : []
  @users = USERS.find({},{:sort => [:user,'ascending']}).to_a
  haml :item
end
post '/itemmessageadd/:id' do
  ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])}, {"$push" => {"messages" => {"text" => params[:text], "date" => Time.now, "author" => @user}}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}})
  logme("added a message to item #{params[:id]}")
  redirect("/item/#{params[:id]}")
end
get '/itemmessagedelete/:id/:index' do
  item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])},{"$pull" => {"messages" => {"text" => item["messages"][params[:index].to_i]["text"],"date" => item["messages"][params[:index].to_i]["date"]}}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}})
  logme("deleted message on item #{params[:id]}")
  redirect back
end
post '/itemtaskadd/:id' do
  item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  order = item["tasks"] ? item["tasks"].size : 0
  ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])}, {"$push" => {"tasks" => {"text" => params[:text], "complete" => false, "order" => order }}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}})
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
  item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  item["tasks"].each_with_index do |t,i|
    ITEMS.update({"_id" => item["_id"]},{"$inc" => {"tasks.#{i}.order" => 1}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}}) if t["order"] == params[:index].to_i
    ITEMS.update({"_id" => item["_id"]},{"$inc" => {"tasks.#{i}.order" => -1}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}}) if t["order"] == params[:index].to_i+1
  end
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
  item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  item["tasks"].each_with_index do |t,i|
    ITEMS.update({"_id" => item["_id"]},{"$inc" => {"tasks.#{i}.order" => -1}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}}) if t["order"] == params[:index].to_i
    ITEMS.update({"_id" => item["_id"]},{"$inc" => {"tasks.#{i}.order" => 1}, "$set" => {"updated_at" => Time.now,"updated_by" => @user}}) if t["order"] == params[:index].to_i-1
  end
  logme("moved down task item #{params[:id]}")
  redirect back
end
get '/items' do 
  @dash         = ITEMS.find({"type" => {"$in" => ["priority","project","prospect","task"]}},{:sort => [:updated_at,'descending'], :limit => 10})
  @priorities   = ITEMS.find({"type" => "priority","archived" => nil},{:sort => [:text,'ascending']})
  @projects     = ITEMS.find({"type" => "project","archived" => nil},{:sort => [:text,'ascending']})
  @prospects    = ITEMS.find({"type" => "prospect","archived" => nil},{:sort => [:text,'ascending']})
  @tasks        = ITEMS.find({"type" => "task", "archived" => nil},{:sort => [:text,'ascending']})
  @random       = ITEMS.find_one({"type" => "random"})
  @myitems      = ITEMS.find({"assigned_user" => @user, "archived" => nil},{:sort => [[:text, 'ascending']]})
  #@chats        = CHATS.find({},{:sort => [:created_at,'descending'],:limit => 25}).to_a.reverse
  @files        = FILES.find({},{:sort => [:upload_date, -1],:limit => 10}).to_a
  #@roster       = ROSTER.find().to_a.map {|m| m["user"]}.join(",")
  @archives     = ITEMS.find({"archived" => true}).count
  #response.set_cookie("last_chat_message",@chats[-1]["_id"])
  haml :items
end
get '/itemarchive/:id' do
  #item = ITEMS.find_one({"_id" => Mongo::ObjectID.from_string(params[:id])})
  ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])}, {"$set" => {"archived" => true, "updated_at" => Time.now, "updated_by" => @user}})
  #archiveitem = ARCHIVE.insert(item)
  #ARCHIVE.update({"_id" => archiveitem},{"$set" => {"updated_at" => Time.now, "updated_by" => @user}})
  #ITEMS.remove({"_id" => Mongo::ObjectID.from_string(params[:id])}, {:safe => true})
  #count = ITEMS.find({"type" => item["type"], "archived" => nil}).count
  #items = ITEMS.find({"type" => item["type"], "archived" => nil},{:sort => ["order",1]})
  #items.each_with_index { |item,i| ITEMS.update({"_id" => item["_id"]},{"$set" => {"order" => i}}) }
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
    assigned_user = nil
    assigned_user, params[:item] = params[:item].split(" ",2) if params[:item][0] == "@"
    id = ITEMS.insert({"type" => params[:type], "text" => params[:item], "assigned_user" => (assigned_user.nil? ? nil : assigned_user[1..-1]), "created_at" => Time.now, "updated_at" => Time.now,"updated_by" => @user}) 
    logme("added item #{id}")
  end
  redirect('/items')
end
get '/itemtoproject/:id' do
  ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])},{"$set" => {"archived" => nil, "type" => "project", "updated_at" => Time.now,"updated_by" => @user}})
  redirect("/item/#{params[:id]}")
end
get '/itemtoprospect/:id' do
  ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])},{"$set" => {"type" => "prospect", "updated_at" => Time.now,"updated_by" => @user}})
  redirect back
end
get '/itemtotask/:id' do
  ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])},{"$set" => {"type" => "task", "updated_at" => Time.now,"updated_by" => @user}})
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
  ITEMS.update({"_id" => Mongo::ObjectID.from_string(params[:id])},{"$set" => {"text" => params[:text], "assigned_user" => params[:assigned_user].downcase, "blob" => params[:blob], "updated_at" => Time.now,"updated_by" => @user}})
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
  @tempuser = USERS.find_one({"user" => params[:user].downcase, "pwdmd5" => Digest::MD5.hexdigest(params[:pass])})
  if @tempuser
    response.set_cookie("applabs_team_tracker_logged_in", params[:user].downcase)
    USERS.update({"_id" => @tempuser["_id"]},{"$set" => {"lastlogin_at" => Time.now}})
    logme("#{params[:user].downcase} logged in")
    redirect('/items')
  else
    redirect('/')
  end
end
get '/logout' do
  response.set_cookie("applabs_team_tracker_logged_in", nil)
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
  ITEMS.update({"type" => params[:item]}, {"$set" => {"text" => params[:text], "updated_at" => Time.now,"updated_by" => @user}})
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
    data.each_with_index do |d,i|
      tskopen = 0
      d["tasks"].each { |t| tskopen += 1 if not t["complete"] } if d["tasks"]
      html += "<li><a href='/item/#{d["_id"]}'>#{d["text"]}#{(not d["assigned_user"].nil? and not d["assigned_user"].empty?) ? "[#{d["assigned_user"].capitalize}]" : nil}</a> <span class='meta'>(#{d["messages"] ? "msg:#{d["messages"].size}" : "msg:0"}, tsk:#{tskopen})</span>"
    end
    html += "</ul>"
    html += "&nbsp;&nbsp;No items." if data.count == 0
    html
  end
  def logme(what)
    LOG.insert({"who" => @user, "what" => what, "when" => Time.now})
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
                         background-image: -webkit-gradient(linear, left top, left -100%, from(#DDE5F0), to(#FFFFFF)); } 
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
    %b= i["type"].upcase
    = "<a href='/archiveitem/#{i["_id"]}'>#{i["text"]}</a>"
    = "<i>(#{i["created_at"].localtime.strftime("%Y%m%d %I:%M %p")}, msg: #{i["messages"] ? i["messages"].size : 0}, tsk: #{i["tasks"] ? i["tasks"].size : 0})</i>"
    = "<a class='nounderline' href='/archivedelete/#{i["_id"]}'>&#215;</a>"
    = "<a class='nounderline' href='/archiverestore/#{i["_id"]}'>&larr;</a>"

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
%h2= "#{@item["archived"].nil? ? @item["type"].upcase : "ARCHIVE"}: #{@item["text"]}"
%p= "<i>Last modified by #{@item["updated_by"].capitalize} on #{@item["updated_at"].localtime.strftime("%Y-%m-%d at %I:%M %p")}.</i>"
#leftcolumn
  - if @archive
    %a{ :href => "/archive" }= "Back to Archive"
    |
    %a{ :href => "/itemtoproject/#{@item["_id"]}" }= "Convert to Project"
    | 
    %a{ :href => "/items" }= "Back to Home"
  - else
    %a{ :href => "/items" }= "Back to Home"
    - if @item["type"] != "task"
      |
      %a{ :href => "/itemtotask/#{@item["_id"]}" }= "Convert to Task"
    - if @item["type"] != "project"
      |
      %a{ :href => "/itemtoproject/#{@item["_id"]}" }= "Convert to Project"
    - if @item["type"] != "prospect"
      |
      %a{ :href => "/itemtoprospect/#{@item["_id"]}" }= "Convert to Prospect"
    |
    %a{ :href => "/itemarchive/#{@item["_id"]}" }= "Archive"
  %br
  %br
  %form{ :action => "/itemupdate/#{@item["_id"]}", :method => "post" }
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
        %option{ :selected => @item["assigned_user"].nil? }= ""
        - @users.each do |u|
          %option{ :selected => @item["assigned_user"]==u["user"] }= u["user"].capitalize
    %br
    - if not @archive
      %input{ :type => "submit", :value => "Update Item" }
  %h3= "Hours (#{@item["totalhours"].nil? ? "0" : @item["totalhours"].to_i } total)"
  - if not @item["hours"].nil?
    - @item["hours"].each do |h|
      = "[#{h["by"].capitalize} (#{h["byhours"]}) <a href='/itemuserhourinc/#{@item["_id"]}/#{h["by"]}' style='text-decoration:none;'> + </a> <a href='/itemuserhourdec/#{@item["_id"]}/#{h["by"]}' style='text-decoration:none;'> - </a>]"
  - else
    - @users.each do |u|
      = "[#{u["user"].capitalize} (0) <a href='/itemuserhourinc/#{@item["_id"]}/#{u["user"]}' style='text-decoration:none;'> + </a> <a href='/itemuserhourdec/#{@item["_id"]}/#{u["user"]}' style='text-decoration:none;'> - </a>]"
  %h3 Tasks
  - if not @archive
    %form{ :action => "/itemtaskadd/#{params[:id]}", :method => "post" }
      %input{ :type => "text", :name => "text", :size => "60" }
      %input{ :type => "submit", :value => "Add Task" }
  - if @tasks
    - @tasks.each_with_index do |t,i|
      .taskleft
        %form
          - if not @archive
            %input{ :type => "checkbox", :style => "font-size:0.3em;", :checked => t["complete"], :onClick => (@archive ? "" : "this.form.action='/itemtasktoggle/#{@item["_id"]}/#{i}'; this.form.method='POST'; this.form.submit(); return false;") }
      .taskright
        - if @archive
          = " - "
        = "#{t['text']}"
        - if not @archive
          = "<a class='nounderline' href='/itemtaskdelete/#{@item["_id"]}/#{i}'>&#215;</a> #{i>0 ? "<a class='nounderline' href='/itemtaskup/#{@item["_id"]}/#{i}'>&uarr;</a>" : ""} #{i<@item["tasks"].size-1 ? "<a class='nounderline' href='/itemtaskdown/#{@item["_id"]}/#{i}'>&darr;</a>" : ""}"
      .clear
  %br
#rightcolumn
  %h3 Messages
  - if @item["archived"].nil?
    %form{ :action => "/itemmessageadd/#{params[:id]}", :method => "post" }
      %textarea{ :name => "text", :cols => 70, :rows => 5 }
      %br
      %input{ :type => "submit", :value => "Add Message" }
  - if @item["messages"]
    - @item["messages"].sort {|x,y| y["date"] <=> x["date"]}.each_with_index do |m,i|
      %div.message{ :style => "background-color: #{i % 2 == 0 ? "white" : ""};" }
        .messageleft= "#{m['author'] ? "<b>#{m['author'].capitalize}</b>:&nbsp;" : ""}"
        .messageright
          %pre{:style => "font-family:Verdana;margin-top:0px;margin-bottom:0px;padding-bottom:0px;padding-top:0px;"}= "#{m['text']}<br /><i>(#{m['date'].localtime.strftime("%Y-%m-%d")})</i> <a class='nounderline' href='/itemmessagedelete/#{@item["_id"]}/#{@item["messages"].size - i - 1}'>&#215;</a>"
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
    %textarea{ :name => "text", :cols => "70", :rows => "7" }= @random["text"]
    %br
    %input{ :type => "submit", :value => "Update" }
#rightcolumn
  %h3.textright= "Welcome, \"#{@user.capitalize}\" : <a href='/password'>Change Password</a> | <a href='/logout'>Logout</a>"
  %h3 Last 10 Updates
  - @dash.each do |d|
    .dashleft=   "#{d["updated_at"].localtime.strftime("%m/%d %I:%M %p")} "
    .dashmiddle= "<div class=\"dash#{d["type"]}\">#{d["type"]}</div>"
    .dashright=  "<a href='/#{d["archived"].nil? ? "item" : "archiveitem"}/#{d["_id"]}'>#{d["text"][0..35]}#{d["text"].size > 35 ? "..." : ""}</a> (#{d["updated_by"].capitalize})<br />"
    .clear
  %br
  =list(AREAS[1])
  = list(AREAS[3])  # Tasks
  %h3 Files
  %form{:action=>"/fileupload",:method=>"post",:enctype=>"multipart/form-data"}
    %input{:type=>"file",:name=>"file"}
    %input{:type=>"submit",:value=>"Upload"}
  - if @files.size > 0
    %ul
      - @files.each do |f|
        %li= "<a href='/filedownload/#{f["_id"]}'>#{f["filename"]}</a> <a class='nounderline' href='/filedelete/#{f["_id"]}'>&#215;</a>"
  - else
    %p No files uploaded.
  
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

