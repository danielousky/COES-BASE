module ApplicationHelper
	# Enlaces extra inyectados en el sidebar de RailsAdmin (custom actions root)
	# dentro de un grupo de navegación existente, por label de grupo.
	#   { 'NavLabel' => [{ label:, url:, icon:, badge_count: -> {…}, visible_if: ->(user){…} }] }
	SIDEBAR_EXTRA_LINKS = {
		'Planif. Periódica' => [
			{
				label: 'Proceso Graduación',
				url:   '/admin/graduacion',
				icon:  'fa-solid fa-user-graduate',
				# Cacheado: se renderiza en cada página de admin. Invalidado en Grade after_commit.
				badge_count: -> { Rails.cache.fetch('sidebar/posible_graduando_count', expires_in: 5.minutes) { Grade.posible_graduando.count } },
				visible_if:  ->(user) { user&.admin && Ability.new(user).can?(:read, :graduacion) }
			}
		]
	}.freeze

	# Variante de RailsAdmin::ApplicationHelper#main_navigation que inyecta los
	# SIDEBAR_EXTRA_LINKS en el sidebar. Se llama desde
	# layouts/rails_admin/_sidebar_navigation.html.haml en lugar de main_navigation.
	# Si el label del enlace coincide con un grupo de modelos existente, se inyecta
	# ahí; si no (ej. "Reportes"), se renderiza como grupo propio al final.
	def main_navigation_with_extras
		nodes_stack = RailsAdmin::Config.visible_models(controller: controller)
		node_model_names = nodes_stack.collect { |c| c.abstract_model.model_name }
		parent_groups = nodes_stack.group_by { |n| n.parent&.to_s }

		rendered_labels = []
		groups = nodes_stack.group_by(&:navigation_label).collect do |navigation_label, nodes|
			nodes = nodes.select { |n| n.parent.nil? || !n.parent.to_s.in?(node_model_names) }
			li_stack = navigation(parent_groups, nodes) || ''.html_safe
			label = navigation_label || t('admin.misc.navigation')
			rendered_labels << label

			extras = SIDEBAR_EXTRA_LINKS[label]
			li_stack += sidebar_extra_links_stack(extras) if extras

			collapsible_stack(label, 'main', li_stack)
		end

		# Grupos extra cuyo label no corresponde a ningún grupo de modelos (ej. "Reportes").
		SIDEBAR_EXTRA_LINKS.each do |label, links|
			next if rendered_labels.include?(label)
			li_stack = sidebar_extra_links_stack(links)
			groups << collapsible_stack(label, 'main', li_stack) if li_stack.present?
		end

		groups.join.html_safe
	end

	# Renderiza los <li> de un conjunto de enlaces extra del sidebar (respeta
	# visible_if y badge_count). Devuelve html_safe (vacío si ninguno es visible).
	def sidebar_extra_links_stack(links)
		Array(links).each_with_object(''.html_safe) do |link, stack|
			next if link[:visible_if] && !link[:visible_if].call(current_user)
			count = link[:badge_count]&.call
			stack << content_tag(:li) do
				link_to link[:url], class: 'nav-link fw-semibold', data: { turbo: 'false' } do
					icon = content_tag(:i, '', class: "#{link[:icon]} me-2 text-primary")
					label_html = content_tag(:span, link[:label])
					badge = (count.to_i > 0) ? content_tag(:span, count, class: 'badge bg-warning text-dark ms-2') : ''.html_safe
					icon + label_html + badge
				end
			end
		end
	end

	# Header de tabla clickeable para sort server-side. Renderiza un link con
	# flecha ▲▼ del estado actual; al click invierte la dirección.
	def sortable_column_link(label, col, current_sort, current_dir, url_opts = {})
		active = (current_sort == col)
		new_dir = (active && current_dir == 'asc') ? 'desc' : 'asc'
		arrow = active ? (current_dir == 'asc' ? ' ▲' : ' ▼') : ''
		link_to "#{label}#{arrow}".html_safe,
			url_for(url_opts.merge(sort: col, direction: new_dir)),
			class: 'text-decoration-none text-dark'
	end

	def render_haml(haml, locals = {})
		Haml::Engine.new(haml.strip_heredoc, format: :html5).render(locals)
	end

	def to_bs value
		ActionController::Base.helpers.number_to_currency(value, unit: 'Bs.', separator: ",", delimiter: ".")
	end

	def badge_toggle_section_qualified section

		if section.qualified?
			title = 'Habilitar al profesor para calificar de nuevo (Abrir)'
			value = false
			icon = 'fas fa-rotate-right'
			type = 'bg-warning'
		else
			title = 'Marcar como calificada por el profesor (Cerrar)'
			value = true
			icon = 'fas fa-check'
			type = 'bg-success'
		end

		url = "/sections/#{section.id}/change_qualification_status?section[qualified]=#{value}"
		badge_toggle type, icon, url, title, ''
	end

	def badge_toggle type, icon, href, title_tooltip, value, onclick_action=nil

		target = ''
		rel = ''

		if (icon.include? 'fa-download')
			target = '_blank'
			rel = 'noopener noreferrer'
		end
		link_to href, class: "badge #{type}", 'data-bs-toggle': :tooltip,  title: title_tooltip, onclick: onclick_action, target: target, rel: rel do
			capture_haml{"<i class= '#{icon}'></i> #{value}".html_safe}
		end
	end

	def btn_toggle type, icon, href, title_tooltip, value, onclick_action=nil

		target = ''
		rel = ''

		if (icon.include? 'fa-download')
			target = '_blank'
			rel = 'noopener noreferrer'
		end
		link_to href, class: "btn btn-sm #{type}", 'data-bs-toggle': :tooltip, title: title_tooltip, onclick: onclick_action, target: target, rel: rel do
			capture_haml{"<i class= '#{icon}'></i> #{value}".html_safe}
		end
	end

	def btn_toggle_download classes, href, title_tooltip, value, onclick_action=nil
		btn_toggle classes, 'fa fa-download', href, title_tooltip, value, onclick_action
	end
	
	def button_add_section course_id
		content_tag :button, 'data-bs-target': "#NewSectionModal", class: "btn btn-sm btn-success mx-1 addSection", "data-bs-toggle": :modal, course_id: course_id, onclick: "$('#section_course_id').val(this.attributes['course_id'].value);" do
			capture_haml{"<i class='fas fa-plus'></i>".html_safe }
		end
		
	end

	def total_sections_stiky total
		sticky_label 0, 0, 'bg-success', 'text-dark', 'Total Secciones', total
	end

	def sticky_label top, right, bg_color, text_color, title, content
		content_tag :div, 'data-bs-toggle': :tooltip, title: title, class: "btn btn-sm #{bg_color} #{ text_color}", style: "top: #{top}px; right: #{right};font-size: xx-small;" do
			capture_haml{"#{content}".html_safe }
		end	
	end

	
	def link_academic_records_csv object 
		id = object.id
		total = object.academic_records.count
		cod = object.name
		cod ||= object.code
		cod ||= object.id
		model_name = object.class.name
		label_link_with_tooptip("/export_csv/academic_records/#{id}?model_name=#{model_name}", 'bg-success', "<i class='fa-solid fa-user-graduate'></i><i class='fa-solid fa-down-long'></i>", "Descargar #{total} Regisrtos Académicos del #{(translate_model model_name.underscore, 'one').titleize} #{cod}", placement='left') if total > 0
	end

	def link_enroll_academic_process_csv object 
		id = object.id
		total = object.enroll_academic_processes.count
		cod = object.name
		cod ||= object.code
		cod ||= object.id
		model_name = object.class.name
		label_link_with_tooptip("/export_csv/enroll_academic_processes/#{id}?model_name=#{model_name}", 'bg-success', "<i class='fa-solid fa-user-graduate'></i><i class='fa-solid fa-down-long'></i>", "Descargar #{total} Inscritos del #{(translate_model model_name.underscore, 'one').titleize} #{cod}", placement='left') if total > 0
	end	
	
	def label_link_with_tooptip(href, klazz, content, title, placement='top')

		content_tag :a, href: href, rel: :tooltip, 'data-bs-toggle': :tooltip, 'data-bs-placement': placement, 'data-bs-original-title': title do
			capture_haml{"<span class='text-center badge #{klazz}'>#{content}</span>".html_safe }
		end	
	end	

	
	# General Tooltip
	def general_tooltip(content, title, placement='top')
		content_tag :b, rel: :tooltip, 'data-bs-toggle': 'tooltip', 'data-bs-placement': placement, 'data-bs-original-title': title do
			capture_haml{content}
		end	
	end

	# General link
	def general_link(href, content)
		content_tag :a, href: href do
			content
		end
	end

	# General Label
	def label_status(klazz, content, type='badge')
		if content.blank?
			content = 'Sin Información'
			klazz = 'bg-secondary' 
		end
		klazz += ' text-dark' if (klazz.include? 'bg-info')
		capture_haml{"<span class='text-center #{type} #{klazz}'>#{content}</span>".html_safe }
	end

	def link_with_tooltip(href, klazz, content, title, placement='top', label=nil)
		 
		aux = general_link(href, label_status(klazz, content, label) )
		general_tooltip(aux, title, placement)		
	end

	def label_status_with_tooltip(klazz, content, title, placement='top')
		general_tooltip(label_status(klazz, content), title, placement)
	end

	def label_link_with_tooltip(href, klazz, content, title, placement='top')
		if href.blank?
			label_status_with_tooltip(klazz, content, title, placement)
		else
			link_with_tooltip(href, klazz, content, title, placement, 'badge')
		end
	end	

	def btn_link_with_tooptip(href, klazz, content, title, placement='top')
		link_with_tooltip(href, klazz, content, title, placement, 'btn btn-sm')
	end	
	

	def translate_model model, singular='other'
		I18n.t("activerecord.models.#{model}.#{singular}")
	end

	def checkbox_auth id, action, value, area_id, onclick=nil

		content_tag :a do
			check_box_tag "[model#{id}][can_#{action}]", nil, value, {class: "area#{area_id} can_all#{id} read#{id}", onclick: onclick}
		end
	end

	def simple_toggle href, value, title_tooltip, color_type, icon, onclick_action = nil
		target = (href.include? 'descargar') ? '_blank' : ''
		link_to href, class: "tooltip-btn text-#{color_type} btn btn-sm", onclick: onclick_action, target: target, 'data-bs-toggle': :tooltip, title: title_tooltip do
			capture_haml{"<i class= '#{icon}'></i> #{value}".html_safe}
		end

	end

	def signatures

		capture_haml {
			".signatures
				.font-title.text-center FACULTAD
					%table.no_border
						%thead
							%tr
							%th.text-center{style: 'width: 500px'} JURADO EXAMINADOR
							%th.text-center{style: 'width: 500px'} SECRETARÍA
					%br
					%table.no_border
						%thead
							%tr
								%th APELLIDOS Y NOMBRES
								%th FIRMAS
								%th 
							%tr{style: 'height:30px'}
								%th _________________________________
								%th ______________________
								%th NOMBRE ______________________        
							%tr{style: 'height:30px'}
								%th _________________________________
								%th ______________________
								%th FIRMA _______________________
							%tr{style: 'height:30px'}
								%th _________________________________
								%th ______________________
								%th FECHA _______________________"
		}

	end	

end
