"""Focus routing and hero contracts. Animation assets belong to the future UI."""
AGENTS={
'eva':{'name':'Eva','character':'девушка','area':'Коммуникации: почта, рабочие переписки, главное и ответы в стиле руководителя','animation_states':['idle','listening','thinking','speaking','success','error']},
'leo':{'name':'Leo','character':'кот','area':'Команда: поручения, сроки, статусы, просрочки и доступные сведения о рабочем времени','animation_states':['idle','listening','thinking','speaking','success','error']},
'nick':{'name':'Nick','character':'парень','area':'Встречи и расписание: план дня, свободное время, повестка, протокол, поручения и письма','animation_states':['idle','listening','thinking','speaking','success','error']},
'robby':{'name':'Robby','character':'робот','area':'Документы: поиск, сводки, согласования и напоминания','animation_states':['idle','listening','thinking','speaking','success','error']},
}
KEYWORDS={'eva':['письм','почт','переписк','сообщен','ответить','мессенджер'], 'leo':['задач','поручен','сотрудник','срок','команд','просроч','рабочее время'], 'nick':['встреч','календар','протокол','совещан','расписан','повест','созвон'], 'robby':['документ','договор','согласован','регламент','файл','поиск','базе знаний']}
def route(text,requested=None):
    if requested:
        key=requested.lower()
        if key not in AGENTS:raise ValueError('Неизвестный агент')
        return key,'выбран пользователем'
    text=text.lower();counts={name:sum(1 for word in words if word in text) for name,words in KEYWORDS.items()}
    ordered=sorted(counts,key=counts.get,reverse=True)
    if counts[ordered[0]]==0:return None,'не удалось определить агента; уточните запрос или выберите агента'
    if counts[ordered[0]]==counts[ordered[1]]:return None,'запрос относится к нескольким агентам; выберите агента'
    return ordered[0],'выбран по словам в запросе; выбор можно исправить'
