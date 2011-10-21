var last_data={};
var do_reload=0;
var timeout_f;
var update_time=15000;

$(document).ready(function(){
  redraw_data=function(value){
    mode=$("#sensors_type").val();
    if(value == 'do_not_reload'){
      value=last_data;
    }
    else{
      last_data=value;
    }
    $("td[class='node']").css("background-color","#888888").attr("title","no");
    for ( var st in value[mode] ){
      $("#"+st).css("background-color",value[mode][st][0]);
      $("#"+st).attr("title",value[mode][st][1]);
    }
    $("#summary").text(value[mode]['summary']);
    $("#min").text(value[mode]['min']);
    $("#max").text(value[mode]['max']);
    $("#update_button").text("Update").attr("disabled",false);

    if(do_reload>0){
      clearTimeout(timeout_f);
      timeout_f=setTimeout(reload_timer,update_time);
    }
  };

  update_data=function(){
    $("#update_button").text("Updating...").attr("disabled",true);

    mode=$("#sensors_type").val();

    $.ajax({url: "/cgi-bin/online-srcc.cgi",
      type: "POST",
      data: "mode="+mode,
      dataType: "json",
      timeout: update_time,
      success: redraw_data,
      error: function(XMLHttpRequest, textStatus, errorThrown){
          alert("Error:"+textStatus+" = "+errorThrown);
      }
    }); /* jetJSON */
  }; /*change */

  reload_timer=function(){
    if(do_reload>0){
      clearTimeout(timeout_f);
      update_data();
    }
  };
  $("#sensors_type").change(function(){redraw_data('do_not_reload')});
  $("#update_button").click(update_data);

  $('input[name="reload_check"]').change(function(){
    if($('input[name="reload_check"]').attr('checked')){
      do_reload=1;
      reload_timer();
    }else{
      do_reload=0;
      clearTimeout(timeout_f);
    }
  });/* reload checkbox */

  $("td[class='node']").mouseenter(
    function(e){
      $("#current").text($("#"+e.currentTarget.id).attr("title"));
    }
  );

  update_data();
}); /* document */
