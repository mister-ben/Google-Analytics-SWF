/**
 * Brightcove Google Analytics SWF 2.0.0 (2014-08-22)
 *
 * REFERENCES:
 *	 Website: http://opensource.brightcove.com
 *	 Source: http://github.com/brightcoveos
 *
 * AUTHORS:
 *	 Brandon Aaskov <baaskov@brightcove.com>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the “Software”),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, alter, merge, publish, distribute,
 * sublicense, and/or sell copies of the Software, and to permit persons to
 * whom the Software is furnished to do so, subject to the following conditions:
 *   
 * 1. The permission granted herein does not extend to commercial use of
 * the Software by entities primarily engaged in providing online video and
 * related services.
 *  
 * 2. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT ANY WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, SUITABILITY, TITLE,
 * NONINFRINGEMENT, OR THAT THE SOFTWARE WILL BE ERROR FREE. IN NO EVENT
 * SHALL THE AUTHORS, CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY WHATSOEVER, WHETHER IN AN ACTION OF
 * CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
 * THE SOFTWARE OR THE USE, INABILITY TO USE, OR OTHER DEALINGS IN THE SOFTWARE.
 *  
 * 3. NONE OF THE AUTHORS, CONTRIBUTORS, NOR BRIGHTCOVE SHALL BE RESPONSIBLE
 * IN ANY MANNER FOR USE OF THE SOFTWARE.  THE SOFTWARE IS PROVIDED FOR YOUR
 * CONVENIENCE AND ANY USE IS SOLELY AT YOUR OWN RISK.  NO MAINTENANCE AND/OR
 * SUPPORT OF ANY KIND IS PROVIDED FOR THE SOFTWARE.
 */

package {
	import com.brightcove.api.APIModules;
	import com.brightcove.api.CustomModule;
	import com.brightcove.api.dtos.RenditionAssetDTO;
	import com.brightcove.api.dtos.VideoDTO;
	import com.brightcove.api.events.AdEvent;
	import com.brightcove.api.events.CuePointEvent;
	import com.brightcove.api.events.ExperienceEvent;
	import com.brightcove.api.events.MediaEvent;
	import com.brightcove.api.modules.AdvertisingModule;
	import com.brightcove.api.modules.CuePointsModule;
	import com.brightcove.api.modules.ExperienceModule;
	import com.brightcove.api.modules.VideoPlayerModule;
	import com.brightcoveos.Action;
	import com.brightcoveos.Category;
	import com.google.analytics.GATracker;
	
	import flash.display.LoaderInfo;
	import flash.net.SharedObject;
	import flash.events.Event;
	import flash.events.SecurityErrorEvent;
	import flash.events.IOErrorEvent;
	import flash.net.URLRequest;
	import flash.display.Loader;

	public class GoogleAnalytics extends CustomModule
	{
		/*
		This account ID can be hardcoded here, or passed in via a parameter on the plugin, 
		in the embed code for the player, or the URL of the page.
		
		1) Plugin Parameter: http://mydomain.com/GoogleAnalytics.swf?accountNumber=UA-123456-0
		2) Embed Code Parameter: <param name="accountNumber" value="UA-123456-0" />
		3) Page URL: http://somedomain.com/section/category/page?accountNumber=UA-123456-0
		*/
		private static var ACCOUNT_NUMBER:String = "";
		private static const VERSION:String = "2.0.0";
		
		private var _experienceModule:ExperienceModule;
		private var _videoPlayerModule:VideoPlayerModule;
		private var _cuePointsModule:CuePointsModule;
		private var _advertisingModule:AdvertisingModule;
		private var _currentVideo:VideoDTO;
		private var _customVideoID:String;
		private var _currentRendition:RenditionAssetDTO;
		
		private var _debugEnabled:Boolean = false;
		private var _tracker:GATracker;
		private var _currentPosition:Number;
		private var _previousTimestamp:Number;
		private var _timeWatched:Number; //stored in milliseconds
		private var _storedTimeWatched:SharedObject = SharedObject.getLocal("previousVideo");

		private var _universal:Boolean = false;
		private var _ni:Boolean = false;

		//flags for tracking
		private var _mediaBegin:Boolean = false;
		private var _mediaComplete:Boolean = true;
		private var _mediaPaused:Boolean = false;
		private var _mediaSeeking:Boolean = false;
		private var _videoMuted:Boolean = false;
		private var _trackSeekForward:Boolean = false;
		private var _trackSeekBackward:Boolean = false;
		
    public function GoogleAnalytics():void
    {
      trace("@project GoogleAnalytics");
      trace("@author Brandon Aaskov");
      trace("@author misterben");
      trace("@lastModified 2014-08-22 12:23 UTC");
    }
    
		override protected function initialize():void
		{
			_experienceModule = player.getModule(APIModules.EXPERIENCE) as ExperienceModule;
			_videoPlayerModule = player.getModule(APIModules.VIDEO_PLAYER) as VideoPlayerModule;
			_cuePointsModule = player.getModule(APIModules.CUE_POINTS) as CuePointsModule;
			_advertisingModule = player.getModule(APIModules.ADVERTISING) as AdvertisingModule;
			
			debug("Version " + GoogleAnalytics.VERSION);
			_debugEnabled = (getParamValue('debug') == "true") ? true : false;

			_universal = (getParamValue('universal') == "true") ? true : false;
			if (_universal) {
				debug("Universal Analytics");
				_ni = (getParamValue('ni') == "true") ? true : false;
				if (_ni) {
					debug("Using non interaction");
				}
			}
			
			setupEventListeners();
			
			setAccountNumber();
			setPlayerType();
			
			
			debug("GA Debug Enabled = " + _debugEnabled);
			if ( !_universal ) {
				_tracker = new GATracker(_experienceModule.getStage(), GoogleAnalytics.ACCOUNT_NUMBER, "AS3", _debugEnabled);
			}
			
			checkAbandonedVideo(); //check if a video didn't get a completion tracked
			
			trackEvent(Category.VIDEO, Action.PLAYER_LOAD, escape(_experienceModule.getExperienceURL()));

			_currentVideo = _videoPlayerModule.getCurrentVideo();
			if (_currentVideo) {
				_customVideoID = getCustomVideoID(_currentVideo);
				_storedTimeWatched.data.abandonedVideo = _currentVideo;
				createCuePoints(_currentVideo);
				trackEvent(Category.VIDEO, Action.VIDEO_LOAD, _customVideoID);
				var referrerURL:String = _experienceModule.getReferrerURL();
				var trackingAction:String = Action.REFERRER_URL + referrerURL; //tracks even if referrer URL is not available
				trackEvent(Category.VIDEO, trackingAction, _customVideoID);
			}
			
		}
		
		private function trackEvent(category:String, action:String, label:String=null, value:Number=undefined):void
		{
			if (_universal) {
				// universal
				var payload:String = "v=1&tid=" + ACCOUNT_NUMBER + "&cid=555&t=event";
				payload += "&ec=" + category;
				payload += "&ea=" + action;
				if ( label ) {
					payload += "&el=" + label;
				}
				if ( value.toString() != "NaN" ) {
					payload += "&ev=" + value;
				}
				if ( _ni ) {
					// Non-interaction events seem appropriate for video analytics but doesn't show in real time
					payload += "&ni=1";
				}
				payload += "&time=" + new Date().getTime(); //cachebust
				var req:URLRequest = new URLRequest('http://www.google-analytics.com/collect?'+payload);
			  var l:Loader = new Loader();
			  l.contentLoaderInfo.addEventListener(Event.COMPLETE, cleanup);
			  l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, cleanup);
			  l.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, cleanup);
			  l.load(req);
			  function cleanup(e:Event):void {
			    l.contentLoaderInfo.removeEventListener(Event.COMPLETE, cleanup);
			    l.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, cleanup);
			    l.contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, cleanup);
			  }
			}
			else {
				_tracker.trackEvent(category, action, label, value);
			}
		}

		private function setupEventListeners():void
		{
			_experienceModule.addEventListener(ExperienceEvent.ENTER_FULLSCREEN, onEnterFullScreen);
			_experienceModule.addEventListener(ExperienceEvent.EXIT_FULLSCREEN, onExitFullScreen);
			
			_videoPlayerModule.addEventListener(MediaEvent.CHANGE, onMediaChange);
			_videoPlayerModule.addEventListener(MediaEvent.BEGIN, onMediaBegin);
			_videoPlayerModule.addEventListener(MediaEvent.PLAY, onMediaPlay);
			_videoPlayerModule.addEventListener(MediaEvent.STOP, onMediaStop);
			_videoPlayerModule.addEventListener(MediaEvent.PROGRESS, onMediaProgress);
			_videoPlayerModule.addEventListener(MediaEvent.VOLUME_CHANGE, onVolumeChange);
			_videoPlayerModule.addEventListener(MediaEvent.MUTE_CHANGE, onMuteChange);
			_videoPlayerModule.addEventListener(MediaEvent.SEEK, onSeek);
			_videoPlayerModule.addEventListener(MediaEvent.COMPLETE, onMediaComplete);
			_videoPlayerModule.addEventListener(MediaEvent.RENDITION_CHANGE_COMPLETE, onRenditionChangeComplete);
			
			_cuePointsModule.addEventListener(CuePointEvent.CUE, onCuePoint);
			
			if(_advertisingModule) //check to make sure ads are enabled first
			{
				_advertisingModule.addEventListener(AdEvent.AD_START, onAdStart);
				_advertisingModule.addEventListener(AdEvent.AD_PAUSE, onAdPause);
				_advertisingModule.addEventListener(AdEvent.AD_POSTROLLS_COMPLETE, onAdPostrollsComplete);
				_advertisingModule.addEventListener(AdEvent.AD_RESUME, onAdResume);
				_advertisingModule.addEventListener(AdEvent.AD_COMPLETE, onAdComplete);
				_advertisingModule.addEventListener(AdEvent.EXTERNAL_AD, onExternalAd);
			}
		}
		
		private function onEnterFullScreen(pEvent:ExperienceEvent):void
		{
			trackEvent(Category.VIDEO, Action.ENTER_FULLSCREEN, _customVideoID);
		}
		
		private function onExitFullScreen(pEvent:ExperienceEvent):void
		{
			trackEvent(Category.VIDEO, Action.EXIT_FULLSCREEN, _customVideoID);
		}		
		
		private function onMediaChange(pEvent:MediaEvent):void
		{
			_currentVideo = _videoPlayerModule.getCurrentVideo();
			_customVideoID = getCustomVideoID(_currentVideo);
			_storedTimeWatched.data.abandonedVideo = _currentVideo;
			createCuePoints(_currentVideo);
			
			trackEvent(Category.VIDEO, Action.VIDEO_LOAD, _customVideoID);
			
			_previousTimestamp = new Date().getTime();
			_timeWatched = 0;
		}
		
		private function onMediaBegin(pEvent:MediaEvent):void
		{
			if(!_mediaBegin)
			{
				trackEvent(Category.VIDEO, Action.MEDIA_BEGIN, _customVideoID);
				
				_previousTimestamp = new Date().getTime();
				_timeWatched = 0;
				
				_mediaComplete = false;
				_mediaBegin = true;
			}
		}
		
		private function onMediaPlay(pEvent:MediaEvent):void
		{
			if(!_mediaBegin)
			{
				//PD videos don't fire mediaPlay when the video starts the first time around, so we'll track it manually 
				onMediaBegin(pEvent);	
			}
			
			if(_mediaPaused)
			{
				debug('Media resume');
				_mediaPaused = false;
				trackEvent(Category.VIDEO, Action.MEDIA_RESUME, _customVideoID);
			}
		}
		
		private function onMediaStop(pEvent:MediaEvent):void
		{
			if(!_mediaComplete && !_mediaPaused)
			{
				_mediaPaused = true;
				trackEvent(Category.VIDEO, Action.MEDIA_PAUSE, _customVideoID);
			}
		}
		
		private function onMediaProgress(pEvent:MediaEvent):void
		{
			_currentPosition = pEvent.position;
			updateTrackedTime();
			
			/*
			This will track the media complete event when the user has watched 98% or more of the video. 
			Why do it this way and not use the Player API's event? The mediaComplete event will 
			only fire once, so if a video is replayed, it won't fire again. Why 98%? If the video's 
			duration is 3 minutes, it might really be 3 minutes and .145 seconds (as an example). When 
			we track the position here, there's a very high likelihood that the current position will 
			never equal the duration's value, even when the video gets to the very end. We use 98% since 
			short videos may never see 99%: if the position is 15.01 seconds and the video's duration 
			is 15.23 seconds, that's just over 98% and that's not an unlikely scenario. If the video is 
			long-form content (let's say an hour), that leaves 1.2 minutes of video to play before the 
			true end of the video. However, most content of that length has credits where a user will 
			drop off anyway, and in most cases content owners want to still track that as a media 
			complete event. Feel free to change this logic as needed, but do it cautiously and test as 
			much as you possibly can!
			*/
			if(pEvent.position/pEvent.duration > .98 && !_mediaComplete)
			{
				onMediaComplete(pEvent);
				
				//empty these since we don't want to track it when someone comes back
				_storedTimeWatched.data.abandonedVideo = null;
				_storedTimeWatched.data.abandonedTimeWatched = null;
			}
			
			
			//track seek events
			if(!_mediaSeeking)
			{
				if(_trackSeekForward)
				{
					trackEvent(Category.VIDEO, Action.SEEK_FORWARD, _customVideoID);
					_trackSeekForward = false;
				}
				
				if(_trackSeekBackward)
				{
					trackEvent(Category.VIDEO, Action.SEEK_BACKWARD, _customVideoID);
					_trackSeekBackward = false;
				}
			}
			else
			{
				_mediaSeeking = false;
			}
		}
		
		/**
		 * This gets fired from the onMediaProgress handler and not from the Player API. Also 
		 * tracks the total time watched by the user for the video.
		 */ 
		private function onMediaComplete(pEvent:MediaEvent):void
		{
			if(!_mediaComplete)
			{
				_mediaComplete = true;
				_mediaBegin = false;
			
				trackEvent(Category.VIDEO, Action.MEDIA_COMPLETE, _customVideoID, Math.round(_timeWatched));
			}
		}
		
		private function onRenditionChangeComplete(pEvent:MediaEvent):void
		{
			var rendition:RenditionAssetDTO = pEvent.rendition as RenditionAssetDTO;
			var encodingRate:uint = Math.round(rendition.encodingRate/1000);
			
			if(_currentRendition)
			{				
				if(rendition.encodingRate > _currentRendition.encodingRate)
				{
					//rendition change increase
					trackEvent(Category.VIDEO, Action.RENDITION_CHANGE_INCREASE, _customVideoID, encodingRate);
				}
				else if(rendition.encodingRate < _currentRendition.encodingRate)
				{
					//rendition change decrease
					trackEvent(Category.VIDEO, Action.RENDITION_CHANGE_DECREASE, _customVideoID, encodingRate);
				}
			}

			_currentRendition = rendition;
		}
		
		private function onVolumeChange(pEvent:MediaEvent):void
		{
			var volume:Number = _videoPlayerModule.getVolume();
			
			if(volume == 0)
			{
				_videoMuted = true;
				
				trackEvent(Category.VIDEO, Action.VIDEO_MUTED, _customVideoID);
			}
			else
			{
				if(_videoMuted)
				{
					_videoMuted = false;
					
					trackEvent(Category.VIDEO, Action.VIDEO_UNMUTED, _customVideoID);
				}
			}
		}
		
		private function onMuteChange(pEvent:MediaEvent):void
		{
			if(_videoPlayerModule.isMuted())
			{
				trackEvent(Category.VIDEO, Action.VIDEO_MUTED, _customVideoID);
			}
			else
			{
				trackEvent(Category.VIDEO, Action.VIDEO_UNMUTED, _customVideoID);
			}
		}
		
		private function onSeek(pEvent:MediaEvent):void
		{
			if(pEvent.position > _currentPosition)
			{
				_trackSeekForward = true;
			}
			else
			{
				_trackSeekBackward = true;	
			}
			
			_mediaSeeking = true;
		}
		
		private function onCuePoint(pEvent:CuePointEvent):void
		{
			if(pEvent.cuePoint.type == 2 && pEvent.cuePoint.name == "milestone")
            {   
                switch(pEvent.cuePoint.metadata)
                {
                	case "25%":
                		trackEvent(Category.VIDEO, Action.MILESTONE_25, _customVideoID);
                		break;
                	case "50%":
                		trackEvent(Category.VIDEO, Action.MILESTONE_50, _customVideoID);
                		break;
                	case "75%":
                		trackEvent(Category.VIDEO, Action.MILESTONE_75, _customVideoID);
                		break;
                }
            }
		}
		
		/**
         * @private
         */
        protected function createCuePoints(pVideo:VideoDTO):void
        {
            var percent25:Object = {
                type: 2, //chapter cue point
                name: "milestone",
                metadata: "25%",
                time: (pVideo.length/1000) * .25
            };
            var percent50:Object = {
                type: 2, //chapter cue point
                name: "milestone",
                metadata: "50%",
                time: (pVideo.length/1000) * .5
            };
            var percent75:Object = {
                type: 2, //chapter cue point
                name: "milestone",
                metadata: "75%",
                time: (pVideo.length/1000) * .75
            };
            
            _cuePointsModule.addCuePoints(_currentVideo.id, [percent25, percent50, percent75]);
        }
        
        private function onAdStart(pEvent:AdEvent):void
        {
        	trackEvent(Category.VIDEO, Action.AD_START, _customVideoID);
        }
        
        private function onAdPause(pEvent:AdEvent):void
        {
        	trackEvent(Category.VIDEO, Action.AD_PAUSE, _customVideoID);
        }
       
        private function onAdPostrollsComplete(pEvent:AdEvent):void
        {
        	trackEvent(Category.VIDEO, Action.AD_POSTROLLS_COMPLETE, _customVideoID);
        }
        
        private function onAdResume(pEvent:AdEvent):void
        {
        	trackEvent(Category.VIDEO, Action.AD_RESUME, _customVideoID);
        }
        
        private function onAdComplete(pEvent:AdEvent):void
        {
        	trackEvent(Category.VIDEO, Action.AD_COMPLETE, _customVideoID);
        }
        
        private function onExternalAd(pEvent:AdEvent):void
        {
        	trackEvent(Category.VIDEO, Action.EXTERNAL_AD, _customVideoID);
        }

		
		/**
		 * Keeps track of the aggregate time the user has been watching the video. If a user watches 10 seconds, 
		 * skips forward, watches another 10 seconds, skips again and watches 30 more seconds, the _timeWatched 
		 * will track as 50 seconds when the mediaComplete event fires. 
		 */ 
		private function updateTrackedTime():void
		{
			var currentTimestamp:Number = new Date().getTime();
			var timeElapsed:Number = (currentTimestamp - _previousTimestamp)/1000;
			_previousTimestamp = currentTimestamp;
			
			//check if it's more than 2 seconds in case the user paused or changed their local time or something
			if(timeElapsed < 2) 
			{
				_timeWatched += timeElapsed;
			}  
			
			//update time watched in case the user bails out before mediaComplete
			if(!_mediaComplete) //make sure mediaComplete hasn't fired yet, otherwise it gets set to null and the repopulated: not what we want
			{
				_storedTimeWatched.data.abandonedTimeWatched = _timeWatched; //automatically gets flushed when flash player is closed	
			}	
		}
		
		private function setAccountNumber():void
		{
			GoogleAnalytics.ACCOUNT_NUMBER = getParamValue('accountNumber');
			
			if(!GoogleAnalytics.ACCOUNT_NUMBER)
			{
				throw new Error('The Google Analytics account number has not been defined. This is required for the analytics SWF to function properly.');
			}
			else
			{
				debug("Account Number = " + GoogleAnalytics.ACCOUNT_NUMBER);
			}
		}
		
		private function setPlayerType():void
		{
			var playerType:String = unescape(getParamValue('playerType'));
			
			if(playerType && playerType != "null")
			{
				if(playerType == "{playername}")
				{
					Category.VIDEO = _experienceModule.getPlayerName();
				}
				else
				{
					Category.VIDEO = playerType;	
				}
			}
			else
			{
				Category.VIDEO = "Brightcove Player";
			}
			
			debug("playerType = " + Category.VIDEO);
		}
		
		private function checkAbandonedVideo():void
		{
			if(_storedTimeWatched.data.abandonedVideo && _storedTimeWatched.data.abandonedTimeWatched)
			{
				var customVideoID:String = getCustomVideoID(_storedTimeWatched.data.abandonedVideo);
				var timeWatched:Number = Math.round(_storedTimeWatched.data.abandonedTimeWatched);
				
				debug("Tracking video that was previously unclosed: " + customVideoID + " : " + timeWatched);
				trackEvent(Category.VIDEO, Action.MEDIA_ABANDONED, customVideoID, timeWatched);
			}
		}
		
		private function getCustomVideoID(currentVideo:VideoDTO):String
		{
			var customVideoID:String = currentVideo.id + " | " + currentVideo.displayName;
			return customVideoID;
		}
		
		private function debug(message:String):void
		{
			_experienceModule.debug("GoogleAnalytics: " + message);
		}
		
		/**
		 * Looks for the @param key in the URL of the page, the publishing code of the player, and 
		 * the URL for the SWF itself (in that order) and returns its value.
		 */
		public function getParamValue(key:String):String
		{
			//1: check url params for the value
			var url:String = _experienceModule.getExperienceURL();
			if(url.indexOf("?") !== -1)
			{
				var urlParams:Array = url.split("?")[1].split("&");
				for(var i:uint = 0; i < urlParams.length; i++)
				{
					var keyValuePair:Array = urlParams[i].split("=");
					if(keyValuePair[0] == key) 
					{
						return keyValuePair[1];
					}
				}
			}
			
			//2: check player params for the value
			var playerParam:String = _experienceModule.getPlayerParameter(key);
			if(playerParam) 
			{
				return playerParam;
			}
			
			//3: check plugin params for the value
			var pluginParams:Object = LoaderInfo(this.root.loaderInfo).parameters;
			for(var param:String in pluginParams)
			{
				if(param == key) 
				{
					return pluginParams[param];
				}
			}
					
			return null;
		}
	}
}
