document.addEventListener('DOMContentLoaded', (event) => {
    var agreeCheckBox = document.getElementById("js-agreeCheckBox");
    var agreeNextLink = document.getElementById("js-agreeNextLink");
    var nextUrl = agreeNextLink.dataset.link;
    var setClass = "disable-link";
    //checkboxの変更
    agreeCheckBox.addEventListener('change', (event) => {
      let isChecked = event.target.checked;
      if(isChecked){
        agreeNextLink.href = nextUrl;
        agreeNextLink.classList.remove(setClass);
      }else{
        agreeNextLink.href = "javascript:void(0)";
        agreeNextLink.classList.add(setClass);
      }
    });
  });