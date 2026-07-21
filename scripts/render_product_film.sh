#!/usr/bin/env bash
# Render the live Apple-style product film from synchronized application footage.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
live_dir="${1:-${repo_dir}/captures/v1.0.0-beta.1/raw/live}"
output_dir="${2:-${repo_dir}/captures/v1.0.0-beta.1/final}"
hub_landscape="${live_dir}/edgehub-live-hub-landscape.mp4"
hub_portrait="${live_dir}/edgehub-live-hub-portrait.mp4"
manager_root="${live_dir}/edgehub-live-manager-root.mp4"
orientation_hub_root="${live_dir}/edgehub-live-orientation-hub-root.mp4"
orientation_manager_root="${live_dir}/edgehub-live-orientation-manager-root.mp4"
device_frame="${repo_dir}/assets/marketing/edge-device-frame.svg"
monitor_frame="${repo_dir}/assets/marketing/desktop-monitor-frame.svg"
font_regular="${repo_dir}/assets/fonts/Lexend-Regular.ttf"
font_bold="${repo_dir}/assets/fonts/Lexend-Bold.ttf"
product_icon="${repo_dir}/assets/icon/hicolor/512x512/apps/xeneon-edge-hub.png"
sky_logo="${repo_dir}/assets/branding/sky-white.png"
work_dir="$(mktemp -d -p /tmp edgehub-product-film.XXXXXX)"
trap 'rm -rf -- "$work_dir"' EXIT INT TERM

for source in "$hub_landscape" "$hub_portrait" "$manager_root" \
              "$orientation_hub_root" "$orientation_manager_root" \
              "$device_frame" "$monitor_frame" "$font_regular" "$font_bold" \
              "$product_icon" "$sky_logo"; do
    [ -s "$source" ] || { echo "missing product-film input: $source" >&2; exit 2; }
done
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is required" >&2; exit 2; }
command -v ffprobe >/dev/null 2>&1 || { echo "ffprobe is required" >&2; exit 2; }
install -d "$output_dir" "$work_dir/clips"

encode=( -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p -r 30 -an )

# 1. Push into the real running Hub inside a hardware-shaped frame.
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "gradients=s=1920x1080:r=30:d=7:c0=0xf7f9fc:c1=0xdce7f3:x0=100:y0=0:x1=1800:y1=1080:speed=0" \
    -i "$hub_landscape" -loop 1 -framerate 30 -i "$device_frame" \
    -filter_complex "
      [1:v]trim=0:7,setpts=PTS-STARTPTS,scale=1428:402[hub];
      [2:v]scale=1600:620,format=rgba[frame];
      [0:v][hub]overlay=246:335[a];
      [a][frame]overlay=160:230[scene];
      [scene]scale=7680:4320:flags=lanczos[scene-hi];
      [scene-hi]zoompan=z='min(1.10,1+on*0.00048)':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s=1920x1080:fps=30[zoom];
      [zoom]drawtext=fontfile='${font_bold}':text='Leaving Windows behind?':fontcolor=0x121722:fontsize=50:x=(w-text_w)/2:y=72:alpha='if(lt(t,0.5),t/0.5,if(lt(t,2.7),1,if(lt(t,3.5),(3.5-t)/0.8,0)))',
            drawtext=fontfile='${font_bold}':text='Your Edge can come with you.':fontcolor=0x121722:fontsize=50:x=(w-text_w)/2:y=72:alpha='if(lt(t,2.9),0,if(lt(t,3.7),(t-2.9)/0.8,if(lt(t,6.2),1,(7-t)/0.8)))',
            drawtext=fontfile='${font_regular}':text='Meet EdgeHub for Linux.':fontcolor=0x4d5a6c:fontsize=24:x=(w-text_w)/2:y=146:alpha='if(lt(t,0.8),t/0.8,if(lt(t,6.2),1,(7-t)/0.8))',
            fade=t=in:st=0:d=0.35,format=yuv420p[v]" \
    -map "[v]" -t 7 "${encode[@]}" "$work_dir/clips/01-intro.mp4"

# 2. Rotate the full front-facing silhouette and cross into a live portrait reflow.
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "gradients=s=1920x1080:r=30:d=4.5:c0=0x0a1020:c1=0x203a5a:x0=0:y0=0:x1=1920:y1=1080:speed=0" \
    -ss 6 -t 4.5 -i "$hub_landscape" -stream_loop -1 -i "$hub_portrait" \
    -loop 1 -framerate 30 -i "$device_frame" \
    -filter_complex "
      [1:v]trim=0:4.5,setpts=PTS-STARTPTS,scale=1428:402[land];
      [2:v]trim=0:4.5,setpts=PTS-STARTPTS,scale=402:1428,transpose=cclock[portrait-sideways];
      [land][portrait-sideways]xfade=transition=fade:duration=0.55:offset=1.25[screen];
      color=c=black@0:s=1600x620:r=30:d=4.5,format=rgba[clear];
      [3:v]scale=1600:620,format=rgba[frame];
      [clear][screen]overlay=86:105:format=auto[a];
      [a][frame]overlay=0:0:format=auto,scale=900:349,
        pad=1000:1000:50:325:color=black@0,format=rgba,
        rotate='(PI/2)*if(lt(t,0.65),0,if(gt(t,2.15),1,pow((t-0.65)/1.5,2)*(3-2*(t-0.65)/1.5)))':ow=1000:oh=1000:c=none[turn];
      [0:v][turn]overlay=(W-w)/2:(H-h)/2[scene];
      [scene]drawtext=fontfile='${font_bold}':text='Landscape. Portrait.':fontcolor=white:fontsize=50:x=90:y=90:alpha='min(1,t/0.45)*if(lt(t,3.7),1,max(0,(4.4-t)/0.7))',
             drawtext=fontfile='${font_regular}':text='A smooth turn. An instant reflow.':fontcolor=0xb9c9dc:fontsize=24:x=94:y=158:alpha='min(1,t/0.45)*if(lt(t,3.7),1,max(0,(4.4-t)/0.7))',
             format=yuv420p[v]" \
    -map "[v]" -t 4.5 "${encode[@]}" "$work_dir/clips/02-rotate.mp4"

# 3. Reveal Manager following the same portrait-to-landscape change live.
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "gradients=s=1920x1080:r=30:d=9:c0=0xf7f8fb:c1=0xd8e3ef:x0=150:y0=0:x1=1780:y1=1080:speed=0" \
    -ss 6 -t 9 -i "$orientation_manager_root" \
    -ss 6 -t 9 -i "$orientation_hub_root" \
    -loop 1 -framerate 30 -i "$monitor_frame" \
    -loop 1 -framerate 30 -i "$device_frame" \
    -filter_complex "
      [1:v]trim=0:9,setpts=PTS-STARTPTS,crop=1440:1000:240:40,scale=928:645[manager];
      [2:v]trim=0:9,setpts=PTS-STARTPTS,transpose=cclock,scale=785:221[hub];
      [3:v]scale=1120:800,format=rgba[monitor-frame];
      [4:v]scale=880:341,format=rgba[edge-frame];
      color=c=black@0:s=880x341:r=30:d=9,format=rgba[clear];
      [clear][hub]overlay=47:58:format=auto[device-screen];
      [device-screen][edge-frame]overlay=0:0:format=auto,
        pad=900:900:10:279:color=black@0,format=rgba,
        rotate='(PI/2)*(1-if(lt(t,4.35),0,if(gt(t,5.15),1,pow((t-4.35)/0.8,2)*(3-2*(t-4.35)/0.8))))':ow=900:oh=900:c=none[turn];
      [0:v]drawbox=x=0:y=860:w=1920:h=220:color=0xb9c8d8@0.34:t=fill[desk];
      [desk][manager]overlay=146:102[a];
      [a][monitor-frame]overlay=50:50[b];
      [b][turn]overlay=x=950:y='150+241*if(lt(t,5.2),0,if(gt(t,8.2),1,pow((t-5.2)/3,2)*(3-2*(t-5.2)/3)))'[scene];
      [scene]split=2[orientation-zoom-source][orientation-steady-source];
      [orientation-zoom-source]trim=0:3.1,setpts=PTS-STARTPTS,scale=7680:4320:flags=lanczos[orientation-hi];
      [orientation-hi]zoompan=z='max(1,1.30-0.30*on/90)':x='(iw-iw/zoom)*0.92':y='(ih-ih/zoom)*0.55':d=1:s=1920x1080:fps=30[orientation-zoom];
      [orientation-steady-source]trim=start=3.1,setpts=PTS-STARTPTS[orientation-steady];
      [orientation-zoom][orientation-steady]concat=n=2:v=1:a=0[orientation-camera];
      [orientation-camera]drawtext=fontfile='${font_bold}':text='Turn it. Keep designing.':fontcolor=0x121722:fontsize=40:x=1160:y=82:alpha='if(lt(t,0.6),t/0.6,if(lt(t,8.2),1,(9-t)/0.8))',
             drawtext=fontfile='${font_regular}':text='Manager follows every orientation, live.':fontcolor=0x526479:fontsize=20:x=1163:y=144:alpha='if(lt(t,0.9),t/0.9,if(lt(t,8.2),1,(9-t)/0.8))',
             fade=t=in:st=0:d=0.35,format=yuv420p[v]" \
    -map "[v]" -t 9 "${encode[@]}" "$work_dir/clips/03-live-orientation.mp4"

# 4. Pull back to the separate Manager monitor and show actual live edits.
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "gradients=s=1920x1080:r=30:d=44:c0=0xf7f8fb:c1=0xd8e3ef:x0=150:y0=0:x1=1780:y1=1080:speed=0" \
    -i "$manager_root" -i "$hub_landscape" \
    -loop 1 -framerate 30 -i "$monitor_frame" \
    -loop 1 -framerate 30 -i "$device_frame" \
    -filter_complex "
      [1:v]trim=0:44,setpts=PTS-STARTPTS,crop=1440:1000:240:40,scale=928:645[manager];
      [2:v]trim=0:44,setpts=PTS-STARTPTS,scale=785:221[hub];
      [3:v]scale=1120:800,format=rgba[monitor-frame];
      [4:v]scale=880:341,format=rgba[edge-frame];
      [0:v]drawbox=x=0:y=860:w=1920:h=220:color=0xb9c8d8@0.34:t=fill[desk];
      [desk][manager]overlay=146:102[a];
      [a][monitor-frame]overlay=50:50[b];
      [b][hub]overlay=1007:728[c];
      [c][edge-frame]overlay=960:670[wide];
      [wide]drawtext=fontfile='${font_bold}':text='Your dashboard, on your terms.':fontcolor=0x121722:fontsize=34:x=1200:y=105:alpha='if(lt(t,1.2),0,if(lt(t,2),(t-1.2)/0.8,if(lt(t,8),1,if(lt(t,8.8),(8.8-t)/0.8,0))))',
            drawtext=fontfile='${font_bold}':text='Add. Arrange. Make it yours.':fontcolor=0x121722:fontsize=34:x=1200:y=105:alpha='if(lt(t,8),0,if(lt(t,8.8),(t-8)/0.8,if(lt(t,20),1,if(lt(t,20.8),(20.8-t)/0.8,0))))',
            drawtext=fontfile='${font_bold}':text='One look. Every screen.':fontcolor=0x121722:fontsize=36:x=1200:y=105:alpha='if(lt(t,20),0,if(lt(t,20.8),(t-20)/0.8,if(lt(t,38),1,if(lt(t,38.8),(38.8-t)/0.8,0))))',
            drawtext=fontfile='${font_bold}':text='Your Edge. Your rules.':fontcolor=0x121722:fontsize=36:x=1200:y=105:alpha='if(lt(t,38),0,if(lt(t,38.8),(t-38)/0.8,if(lt(t,43.2),1,(44-t)/0.8)))',
            drawtext=fontfile='${font_regular}':text='LIVE, LOCAL, INSTANT':fontcolor=0x526479:fontsize=17:x=1203:y=168:alpha='if(lt(t,1.2),0,if(lt(t,2),(t-1.2)/0.8,if(lt(t,43.2),1,(44-t)/0.8)))',
            format=yuv420p[v]" \
    -map "[v]" -t 44 "${encode[@]}" "$work_dir/clips/03-live-manager.mp4"

# 5. Finish on the live, newly themed Hub with a branded closing sequence.
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "gradients=s=1920x1080:r=30:d=9:c0=0x090f1e:c1=0x263d5b:x0=200:y0=0:x1=1750:y1=1080:speed=0" \
    -ss 36 -t 9 -stream_loop -1 -i "$hub_landscape" \
    -loop 1 -framerate 30 -i "$device_frame" \
    -loop 1 -framerate 30 -i "$product_icon" \
    -loop 1 -framerate 30 -i "$sky_logo" \
    -filter_complex "
      [1:v]trim=0:9,setpts=PTS-STARTPTS,scale=1142:322[hub];
      [2:v]scale=1280:496,format=rgba[frame];
      [3:v]scale=96:96,format=rgba,fade=t=in:st=4:d=0.8:alpha=1,fade=t=out:st=8.35:d=0.65:alpha=1[icon];
      [4:v]scale=142:-1,format=rgba,fade=t=in:st=0:d=0.5:alpha=1,fade=t=out:st=8.35:d=0.65:alpha=1[brand];
      [0:v][hub]overlay=389:457[a];
      [a][frame]overlay=320:373[scene];
      [scene][brand]overlay=1720:34[branded];
      [branded][icon]overlay=(W-w)/2:36[with-icon];
      [with-icon]drawtext=fontfile='${font_bold}':text='Your favorite features. Your chosen OS.':fontcolor=white:fontsize=52:x=(w-text_w)/2:y=82:alpha='if(lt(t,0.5),t/0.5,if(lt(t,3.4),1,if(lt(t,4.2),(4.2-t)/0.8,0)))',
             drawtext=fontfile='${font_regular}':text='Custom development, built around the way you work.':fontcolor=0xb9c9dc:fontsize=25:x=(w-text_w)/2:y=158:alpha='if(lt(t,0.8),t/0.8,if(lt(t,3.4),1,if(lt(t,4.2),(4.2-t)/0.8,0)))',
             drawtext=fontfile='${font_bold}':text='Build your Edge.':fontcolor=white:fontsize=60:x=(w-text_w)/2:y=154:alpha='if(lt(t,4),0,if(lt(t,4.8),(t-4)/0.8,if(lt(t,8.35),1,(9-t)/0.65)))',
             drawtext=fontfile='${font_regular}':text='EdgeHub for Linux':fontcolor=0xb9c9dc:fontsize=27:x=(w-text_w)/2:y=226:alpha='if(lt(t,4.2),0,if(lt(t,5),(t-4.2)/0.8,if(lt(t,8.35),1,(9-t)/0.65)))',
             drawtext=fontfile='${font_regular}':text='github.com/skyphoenix-it/skyphoenix-edgehub-linux':fontcolor=0x77b8ff:fontsize=20:x=(w-text_w)/2:y=922:alpha='if(lt(t,0.6),t/0.6,if(lt(t,8.35),1,(9-t)/0.65))',
             drawtext=fontfile='${font_bold}':text='TESTED ON':fontcolor=0x9fb3ca:fontsize=14:x=560:y=966:alpha='if(lt(t,0.8),t/0.8,if(lt(t,8.35),1,(9-t)/0.65))',
             drawtext=fontfile='${font_regular}':text='CachyOS (Arch Linux)  |  KDE Plasma  |  Wayland':fontcolor=0xd6e2ef:fontsize=17:x=680:y=964:alpha='if(lt(t,0.8),t/0.8,if(lt(t,8.35),1,(9-t)/0.65))',
             drawtext=fontfile='${font_regular}':text='Independent project. Not affiliated with or endorsed by Corsair.':fontcolor=0x8fa0b4:fontsize=15:x=(w-text_w)/2:y=1014:alpha='if(lt(t,0.8),t/0.8,if(lt(t,8.35),1,(9-t)/0.65))',
             fade=t=in:st=0:d=0.35,fade=t=out:st=8.65:d=0.35,format=yuv420p[v]" \
    -map "[v]" -t 9 "${encode[@]}" "$work_dir/clips/04-end.mp4"

ffmpeg -hide_banner -loglevel error -y \
    -i "$work_dir/clips/01-intro.mp4" -i "$work_dir/clips/02-rotate.mp4" \
    -i "$work_dir/clips/03-live-orientation.mp4" \
    -i "$work_dir/clips/03-live-manager.mp4" -i "$work_dir/clips/04-end.mp4" \
    -filter_complex "
      [0:v]settb=AVTB[v0];[1:v]settb=AVTB[v1];[2:v]settb=AVTB[v2];[3:v]settb=AVTB[v3];[4:v]settb=AVTB[v4];
      [v0][v1]xfade=transition=fade:duration=0.7:offset=6.3[x1];
      [x1][v2]xfade=transition=fade:duration=0.7:offset=10.1[x2];
      [x2][v3]xfade=transition=fade:duration=0.7:offset=18.4[x3];
      [x3][v4]xfade=transition=fade:duration=0.7:offset=61.7[v]" \
    -map "[v]" -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p \
    -r 30 -an "$work_dir/product-film-silent.mp4"

"${repo_dir}/scripts/render_original_soundtrack.sh" 70.7 "$work_dir/product-film.wav"
output="$output_dir/edgehub-v1.0.0-beta.1-live-product-film.mp4"
ffmpeg -hide_banner -loglevel error -y -i "$work_dir/product-film-silent.mp4" \
    -i "$work_dir/product-film.wav" -c:v copy -c:a aac -b:a 192k -shortest \
    -movflags +faststart "$output"

ffmpeg -hide_banner -loglevel error -y -ss 32 -i "$output" -frames:v 1 \
    "$output_dir/edgehub-v1.0.0-beta.1-live-product-film-thumbnail.png"
ffprobe -v error -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate,sample_rate,channels \
    -of json "$output"
