#!/usr/bin/env bash
# Render the live Apple-style product film from synchronized application footage.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
live_dir="${1:-${repo_dir}/captures/v1.0.0-beta.1/raw/live}"
output_dir="${2:-${repo_dir}/captures/v1.0.0-beta.1/final}"
hub_landscape="${live_dir}/edgehub-live-hub-landscape.mp4"
hub_portrait="${live_dir}/edgehub-live-hub-portrait.mp4"
manager_root="${live_dir}/edgehub-live-manager-root.mp4"
device_frame="${repo_dir}/assets/marketing/edge-device-frame.svg"
monitor_frame="${repo_dir}/assets/marketing/desktop-monitor-frame.svg"
font_regular="${repo_dir}/assets/fonts/Lexend-Regular.ttf"
font_bold="${repo_dir}/assets/fonts/Lexend-Bold.ttf"
work_dir="$(mktemp -d -p /tmp edgehub-product-film.XXXXXX)"
trap 'rm -rf -- "$work_dir"' EXIT INT TERM

for source in "$hub_landscape" "$hub_portrait" "$manager_root" \
              "$device_frame" "$monitor_frame" "$font_regular" "$font_bold"; do
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
      [zoom]drawtext=fontfile='${font_bold}':text='Your dashboard. Alive.':fontcolor=0x121722:fontsize=52:x=(w-text_w)/2:y=80:alpha='if(lt(t,0.6),t/0.6,if(lt(t,5.8),1,(7-t)/1.2))',
            drawtext=fontfile='${font_regular}':text='Real EdgeHub output. Real Linux metrics.':fontcolor=0x4d5a6c:fontsize=24:x=(w-text_w)/2:y=150:alpha='if(lt(t,0.9),t/0.9,if(lt(t,5.8),1,(7-t)/1.2))',
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

# 3. Pull back to the separate Manager monitor and show actual live edits.
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
      [wide]zoompan=z='if(lte(on,90),1.32-0.32*on/90,1)':x='(iw-iw/zoom)*0.92':y='(ih-ih/zoom)*0.88':d=1:s=1920x1080:fps=30[pull];
      [pull]drawtext=fontfile='${font_bold}':text='Choose what the Hub shows.':fontcolor=0x121722:fontsize=38:x=1225:y=105:enable='between(t,1.5,8.5)',
            drawtext=fontfile='${font_bold}':text='Screens. Widgets. Layout.':fontcolor=0x121722:fontsize=36:x=1225:y=105:enable='between(t,8.5,20)',
            drawtext=fontfile='${font_bold}':text='Themes and accents. Live.':fontcolor=0x121722:fontsize=36:x=1225:y=105:enable='between(t,20,38)',
            drawtext=fontfile='${font_bold}':text='Device settings. In reach.':fontcolor=0x121722:fontsize=36:x=1225:y=105:enable='between(t,38,43.5)',
            drawtext=fontfile='${font_regular}':text='LOCAL MANAGER TO HUB SYNC':fontcolor=0x526479:fontsize=17:x=1228:y=168:enable='between(t,1.5,43.5)',
            format=yuv420p[v]" \
    -map "[v]" -t 44 "${encode[@]}" "$work_dir/clips/03-live-manager.mp4"

# 4. Finish on the live, newly themed Hub rather than a static card.
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "gradients=s=1920x1080:r=30:d=6:c0=0x090f1e:c1=0x263d5b:x0=200:y0=0:x1=1750:y1=1080:speed=0" \
    -ss 36 -t 6 -stream_loop -1 -i "$hub_landscape" \
    -loop 1 -framerate 30 -i "$device_frame" \
    -filter_complex "
      [1:v]trim=0:6,setpts=PTS-STARTPTS,scale=1142:322[hub];
      [2:v]scale=1280:496,format=rgba[frame];
      [0:v][hub]overlay=389:457[a];
      [a][frame]overlay=320:373[scene];
      [scene]drawtext=fontfile='${font_bold}':text='Build your Edge.':fontcolor=white:fontsize=64:x=(w-text_w)/2:y=92,
             drawtext=fontfile='${font_regular}':text='EdgeHub for Linux':fontcolor=0xb9c9dc:fontsize=28:x=(w-text_w)/2:y=180,
             drawtext=fontfile='${font_regular}':text='github.com/skyphoenix-it/skyphoenix-edgehub-linux':fontcolor=0x77b8ff:fontsize=22:x=(w-text_w)/2:y=950,
             drawtext=fontfile='${font_regular}':text='Independent project. Not affiliated with or endorsed by Corsair.':fontcolor=0x8fa0b4:fontsize=16:x=(w-text_w)/2:y=1002,
             fade=t=in:st=0:d=0.35,fade=t=out:st=5.65:d=0.35,format=yuv420p[v]" \
    -map "[v]" -t 6 "${encode[@]}" "$work_dir/clips/04-end.mp4"

ffmpeg -hide_banner -loglevel error -y \
    -i "$work_dir/clips/01-intro.mp4" -i "$work_dir/clips/02-rotate.mp4" \
    -i "$work_dir/clips/03-live-manager.mp4" -i "$work_dir/clips/04-end.mp4" \
    -filter_complex "
      [0:v]settb=AVTB[v0];[1:v]settb=AVTB[v1];[2:v]settb=AVTB[v2];[3:v]settb=AVTB[v3];
      [v0][v1]xfade=transition=fade:duration=0.7:offset=6.3[x1];
      [x1][v2]xfade=transition=fade:duration=0.7:offset=10.1[x2];
      [x2][v3]xfade=transition=fade:duration=0.7:offset=53.4[v]" \
    -map "[v]" -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p \
    -r 30 -an "$work_dir/product-film-silent.mp4"

"${repo_dir}/scripts/render_original_soundtrack.sh" 59.4 "$work_dir/product-film.wav"
output="$output_dir/edgehub-v1.0.0-beta.1-live-product-film.mp4"
ffmpeg -hide_banner -loglevel error -y -i "$work_dir/product-film-silent.mp4" \
    -i "$work_dir/product-film.wav" -c:v copy -c:a aac -b:a 192k -shortest \
    -movflags +faststart "$output"

ffmpeg -hide_banner -loglevel error -y -ss 32 -i "$output" -frames:v 1 \
    "$output_dir/edgehub-v1.0.0-beta.1-live-product-film-thumbnail.png"
ffprobe -v error -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate,sample_rate,channels \
    -of json "$output"
